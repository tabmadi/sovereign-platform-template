package dbmw

import "testing"

func TestPoolConfigKeepsAtLeastMinPoolConns(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		dsn  string
		want int32
	}{
		{"below the floor", "postgres://u@localhost/db?pool_max_conns=4", minPoolConns},
		{"above the floor", "postgres://u@localhost/db?pool_max_conns=40", 40},
	}
	for _, c := range cases {
		t.Run(
			c.name,
			func(t *testing.T) {
				t.Parallel()
				cfg, err := poolConfig(c.dsn)
				if err != nil {
					t.Fatal(err)
				}
				if cfg.MaxConns != c.want {
					t.Fatalf("MaxConns = %d, want %d", cfg.MaxConns, c.want)
				}
			},
		)
	}
}
