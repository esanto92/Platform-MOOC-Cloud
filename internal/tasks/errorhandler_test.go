package tasks

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"strings"
	"sync"
	"testing"

	"mooc-platform/internal/audit"
)

// Driver falso: solo registra las sentencias que llegan por ExecContext y si
// el contexto ya estaba cancelado en ese momento. Evita depender de Postgres
// o de una libreria de mocks para probar un solo INSERT.
type execRegistrado struct {
	query     string
	cancelado bool
}

type driverFalso struct {
	mu    sync.Mutex
	execs []execRegistrado
}

func (d *driverFalso) Open(string) (driver.Conn, error) { return &connFalsa{d: d}, nil }

type connFalsa struct{ d *driverFalso }

func (c *connFalsa) Prepare(string) (driver.Stmt, error) { return nil, errors.New("no soportado") }
func (c *connFalsa) Close() error                        { return nil }
func (c *connFalsa) Begin() (driver.Tx, error)           { return nil, errors.New("no soportado") }

func (c *connFalsa) ExecContext(ctx context.Context, query string, _ []driver.NamedValue) (driver.Result, error) {
	c.d.mu.Lock()
	defer c.d.mu.Unlock()
	c.d.execs = append(c.d.execs, execRegistrado{query: query, cancelado: ctx.Err() != nil})
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return driver.RowsAffected(1), nil
}

// La alerta de un asset fallido se registra en audit_log aunque el trabajo
// llegue con el contexto cancelado (fallo por timeout o retiro del worker).
// Antes esto lo garantizaba el ErrorHandler de asynq; ahora vive en el dominio
// (alertAssetFailed), asi que la garantia debe conservarse sin la cola.
func TestAlertAssetFailedAuditaAunqueElContextoVengaCancelado(t *testing.T) {
	falso := &driverFalso{}
	sql.Register("falso-errorhandler", falso)
	db, err := sql.Open("falso-errorhandler", "")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	d := &Deps{DB: db, Audit: audit.New(db)}
	d.alertAssetFailed(ctx, "media:transcode", "a1", "ffmpeg no pudo con el archivo")

	falso.mu.Lock()
	defer falso.mu.Unlock()
	if len(falso.execs) != 1 {
		t.Fatalf("se esperaba 1 INSERT de auditoria, hubo %d", len(falso.execs))
	}
	if !strings.Contains(falso.execs[0].query, "INSERT INTO audit_log") {
		t.Fatalf("sentencia inesperada: %s", falso.execs[0].query)
	}
	if falso.execs[0].cancelado {
		t.Fatal("la auditoria se intento con el contexto cancelado; se perderia la alerta del asset fallido")
	}
}
