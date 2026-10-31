package tasks

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"strings"
	"sync"
	"testing"

	"github.com/hibiken/asynq"

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

func TestErrorHandlerAuditaLaDLQAunqueElTrabajoVengaCancelado(t *testing.T) {
	falso := &driverFalso{}
	sql.Register("falso-errorhandler", falso)
	db, err := sql.Open("falso-errorhandler", "")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Un trabajo que agota sus reintentos por timeout llega con el contexto
	// ya cancelado. Sin metadatos de asynq, reintentos y maximo valen 0, asi
	// que el handler toma el camino de la DLQ.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	d := &Deps{Audit: audit.New(db)}
	d.ErrorHandler()(ctx, asynq.NewTask("video:transcode", []byte(`{}`)), context.DeadlineExceeded)

	falso.mu.Lock()
	defer falso.mu.Unlock()
	if len(falso.execs) != 1 {
		t.Fatalf("se esperaba 1 INSERT de auditoria, hubo %d", len(falso.execs))
	}
	if !strings.Contains(falso.execs[0].query, "INSERT INTO audit_log") {
		t.Fatalf("sentencia inesperada: %s", falso.execs[0].query)
	}
	if falso.execs[0].cancelado {
		t.Fatal("la auditoria se intento con el contexto cancelado del trabajo; se perderia la alerta de la DLQ")
	}
}
