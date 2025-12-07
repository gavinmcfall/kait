package main

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestKaitContainer(t *testing.T) {
	ctx := context.Background()

	req := testcontainers.ContainerRequest{
		Image:        "kait:local",
		ExposedPorts: []string{"9000/tcp"},
		WaitingFor:   wait.ForHTTP("/hooks/").WithPort("9000").WithStartupTimeout(30 * time.Second),
	}

	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: req,
		Started:          true,
	})
	if err != nil {
		t.Fatalf("Could not start container: %s", err)
	}
	defer container.Terminate(ctx)

	// Test that kubectl is available
	exitCode, _, err := container.Exec(ctx, []string{"kubectl", "version", "--client"})
	assert.NoError(t, err)
	assert.Equal(t, 0, exitCode, "kubectl should be available")

	// Test that talosctl is available
	exitCode, _, err = container.Exec(ctx, []string{"talosctl", "version", "--client"})
	assert.NoError(t, err)
	assert.Equal(t, 0, exitCode, "talosctl should be available")

	// Test that flux is available
	exitCode, _, err = container.Exec(ctx, []string{"flux", "version", "--client"})
	assert.NoError(t, err)
	assert.Equal(t, 0, exitCode, "flux should be available")
}
