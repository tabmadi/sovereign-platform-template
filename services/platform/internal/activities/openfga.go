package activities

import (
	"context"
	"errors"
	"fmt"
	"net/http"
)

// writeBatch is the most tuple keys that one OpenFGA write accepts.
const writeBatch = 100

type tuple struct {
	User     string `json:"user"`
	Relation string `json:"relation"`
	Object   string `json:"object"`
}

type openFGA struct {
	a      *Activities
	header http.Header
	store  string
}

// openFGA finds the store by name, the same discovery that the services use.
func (a *Activities) openFGA(ctx context.Context) (*openFGA, error) {
	if a.cfg.OpenFGAAPI == "" {
		return nil, errors.New("OPENFGA_API_URL is not set")
	}
	header := http.Header{}
	header.Set("Authorization", "Bearer "+a.cfg.OpenFGAKey)
	var stores struct {
		Stores []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"stores"`
	}
	err := a.do(ctx, http.MethodGet, a.cfg.OpenFGAAPI+"/stores", header, nil, &stores, http.StatusOK)
	if err != nil {
		return nil, fmt.Errorf("list OpenFGA stores: %w", err)
	}
	for _, s := range stores.Stores {
		if s.Name == a.cfg.OpenFGAStore {
			return &openFGA{a: a, header: header, store: s.ID}, nil
		}
	}
	return nil, fmt.Errorf("no OpenFGA store named %q", a.cfg.OpenFGAStore)
}

// subjectTuples reads every tuple whose user is the subject. A read with a user needs an object type, so it reads
// once per type of the latest model. A type added to the model is covered with no change here.
func (f *openFGA) subjectTuples(ctx context.Context, user string) ([]tuple, error) {
	var models struct {
		Models []struct {
			Types []struct {
				Type string `json:"type"`
			} `json:"type_definitions"`
		} `json:"authorization_models"`
	}
	err := f.a.do(
		ctx,
		http.MethodGet,
		f.a.cfg.OpenFGAAPI+"/stores/"+f.store+"/authorization-models?page_size=1",
		f.header,
		nil,
		&models,
		http.StatusOK,
	)
	if err != nil {
		return nil, fmt.Errorf("read the OpenFGA model: %w", err)
	}
	if len(models.Models) == 0 {
		return nil, errors.New("the OpenFGA store has no model")
	}
	var out []tuple
	for _, t := range models.Models[0].Types {
		found, err := f.readType(ctx, user, t.Type)
		if err != nil {
			return nil, err
		}
		out = append(out, found...)
	}
	return out, nil
}

// readType reads every page of the subject's tuples on one object type.
func (f *openFGA) readType(ctx context.Context, user, objectType string) ([]tuple, error) {
	var out []tuple
	token := ""
	for {
		var page struct {
			Tuples []struct {
				Key tuple `json:"key"`
			} `json:"tuples"`
			Token string `json:"continuation_token"`
		}
		req := map[string]any{
			"tuple_key": map[string]string{"user": user, "object": objectType + ":"},
			"page_size": writeBatch,
		}
		if token != "" {
			req["continuation_token"] = token
		}
		err := f.a.do(
			ctx,
			http.MethodPost,
			f.a.cfg.OpenFGAAPI+"/stores/"+f.store+"/read",
			f.header,
			req,
			&page,
			http.StatusOK,
		)
		if err != nil {
			return nil, fmt.Errorf("read %s tuples: %w", objectType, err)
		}
		for _, p := range page.Tuples {
			out = append(out, p.Key)
		}
		if page.Token == "" {
			return out, nil
		}
		token = page.Token
	}
}

func (f *openFGA) delete(ctx context.Context, tuples []tuple) error {
	for start := 0; start < len(tuples); start += writeBatch {
		batch := tuples[start:min(start+writeBatch, len(tuples))]
		err := f.a.do(
			ctx,
			http.MethodPost,
			f.a.cfg.OpenFGAAPI+"/stores/"+f.store+"/write",
			f.header,
			map[string]any{"deletes": map[string]any{"tuple_keys": batch}},
			nil,
			http.StatusOK,
		)
		if err != nil {
			return fmt.Errorf("delete tuples: %w", err)
		}
	}
	return nil
}
