package transport

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func TestClientConnectAndSend(t *testing.T) {
	var mu sync.Mutex
	var received []string

	// Create a test WebSocket server
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			t.Logf("accept error: %v", err)
			return
		}
		defer conn.CloseNow()

		for {
			_, data, err := conn.Read(r.Context())
			if err != nil {
				return
			}
			mu.Lock()
			received = append(received, string(data))
			mu.Unlock()
		}
	}))
	defer srv.Close()

	// Convert http://... to ws://...
	endpoint := "ws" + strings.TrimPrefix(srv.URL, "http")

	client := NewClient(endpoint, "test-token")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Run client in background
	go client.Run(ctx)

	// Wait for connection
	waitForState(t, client, StateConnected, 3*time.Second)

	// Send a message
	msg, err := NewHeartbeatEnvelope("test-token")
	if err != nil {
		t.Fatal(err)
	}
	client.Send(msg)

	// Give server time to receive
	time.Sleep(200 * time.Millisecond)

	cancel()
	time.Sleep(100 * time.Millisecond)

	mu.Lock()
	count := len(received)
	mu.Unlock()

	if count == 0 {
		t.Error("expected at least one message received by server")
	}
}

func TestClientReconnectOnBadEndpoint(t *testing.T) {
	client := NewClient("ws://127.0.0.1:1", "token") // Port 1 should fail

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	go client.Run(ctx)

	// Should see connecting/disconnected states
	select {
	case state := <-client.State():
		if state != StateConnecting {
			t.Errorf("expected first state to be connecting, got %v", state)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for state change")
	}
}

func TestClientUpdateEndpoint(t *testing.T) {
	client := NewClient("ws://127.0.0.1:1", "token")
	client.UpdateEndpoint("ws://127.0.0.1:2")

	if client.endpoint != "ws://127.0.0.1:2" {
		t.Errorf("endpoint not updated: %s", client.endpoint)
	}
}

func waitForState(t *testing.T, c *Client, want ConnState, timeout time.Duration) {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case state := <-c.State():
			if state == want {
				return
			}
		case <-deadline:
			t.Fatalf("timeout waiting for state %v, current: %v", want, c.CurrentState())
		}
	}
}
