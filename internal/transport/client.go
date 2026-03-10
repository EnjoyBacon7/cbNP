package transport

import (
	"context"
	"fmt"
	"log/slog"
	"math"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// ConnState represents the WebSocket connection state.
type ConnState int

const (
	StateDisconnected ConnState = iota
	StateConnecting
	StateConnected
)

func (s ConnState) String() string {
	switch s {
	case StateDisconnected:
		return "disconnected"
	case StateConnecting:
		return "connecting"
	case StateConnected:
		return "connected"
	default:
		return "unknown"
	}
}

// Client manages the WebSocket connection with automatic reconnection.
type Client struct {
	endpoint string
	auth     string

	sendCh  chan []byte
	stateCh chan ConnState

	mu     sync.Mutex
	conn   *websocket.Conn
	state  ConnState
	cancel context.CancelFunc
}

// NewClient creates a new WebSocket client.
func NewClient(endpoint, auth string) *Client {
	return &Client{
		endpoint: endpoint,
		auth:     auth,
		sendCh:   make(chan []byte, 64),
		stateCh:  make(chan ConnState, 8),
	}
}

// Run starts the WebSocket client loop. It connects, reads from the send channel,
// and reconnects with exponential backoff on failure. Blocks until ctx is canceled.
func (c *Client) Run(ctx context.Context) {
	for {
		if ctx.Err() != nil {
			return
		}

		err := c.connectAndServe(ctx)
		if ctx.Err() != nil {
			return
		}

		if err != nil {
			slog.Warn("websocket connection error", "error", err)
		}

		c.setState(StateDisconnected)
		c.backoffReconnect(ctx)
	}
}

func (c *Client) connectAndServe(ctx context.Context) error {
	c.setState(StateConnecting)

	dialCtx, dialCancel := context.WithTimeout(ctx, 10*time.Second)
	defer dialCancel()

	conn, _, err := websocket.Dial(dialCtx, c.endpoint, &websocket.DialOptions{})
	if err != nil {
		return fmt.Errorf("dial %s: %w", c.endpoint, err)
	}

	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

	c.setState(StateConnected)
	slog.Info("websocket connected", "endpoint", c.endpoint)

	// Serve: write messages from sendCh
	for {
		select {
		case <-ctx.Done():
			conn.Close(websocket.StatusNormalClosure, "shutting down")
			return ctx.Err()
		case msg := <-c.sendCh:
			writeCtx, writeCancel := context.WithTimeout(ctx, 5*time.Second)
			err := conn.Write(writeCtx, websocket.MessageText, msg)
			writeCancel()
			if err != nil {
				conn.Close(websocket.StatusInternalError, "write error")
				return fmt.Errorf("write: %w", err)
			}
		}
	}
}

func (c *Client) backoffReconnect(ctx context.Context) {
	const (
		baseDelay = 1 * time.Second
		maxDelay  = 60 * time.Second
	)

	for attempt := 0; ; attempt++ {
		delay := time.Duration(float64(baseDelay) * math.Pow(2, float64(attempt)))
		if delay > maxDelay {
			delay = maxDelay
		}

		slog.Info("reconnecting", "delay", delay, "attempt", attempt+1)

		select {
		case <-ctx.Done():
			return
		case <-time.After(delay):
		}

		// Try to connect
		c.setState(StateConnecting)

		dialCtx, dialCancel := context.WithTimeout(ctx, 10*time.Second)
		conn, _, err := websocket.Dial(dialCtx, c.endpoint, &websocket.DialOptions{})
		dialCancel()

		if err != nil {
			slog.Warn("reconnect failed", "attempt", attempt+1, "error", err)
			continue
		}

		c.mu.Lock()
		c.conn = conn
		c.mu.Unlock()

		c.setState(StateConnected)
		slog.Info("websocket reconnected", "endpoint", c.endpoint)

		// Resume serving
		err = c.serveConn(ctx, conn)
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			slog.Warn("websocket error after reconnect", "error", err)
			c.setState(StateDisconnected)
			// Reset attempt counter partially - use half to avoid immediate max delay
			attempt = attempt / 2
			continue
		}
		return
	}
}

func (c *Client) serveConn(ctx context.Context, conn *websocket.Conn) error {
	for {
		select {
		case <-ctx.Done():
			conn.Close(websocket.StatusNormalClosure, "shutting down")
			return ctx.Err()
		case msg := <-c.sendCh:
			writeCtx, writeCancel := context.WithTimeout(ctx, 5*time.Second)
			err := conn.Write(writeCtx, websocket.MessageText, msg)
			writeCancel()
			if err != nil {
				conn.Close(websocket.StatusInternalError, "write error")
				return fmt.Errorf("write: %w", err)
			}
		}
	}
}

// Send enqueues a message to be sent over the WebSocket.
func (c *Client) Send(msg []byte) {
	select {
	case c.sendCh <- msg:
	default:
		slog.Warn("send channel full, dropping message")
	}
}

// State returns a channel that receives connection state changes.
func (c *Client) State() <-chan ConnState {
	return c.stateCh
}

// CurrentState returns the current connection state.
func (c *Client) CurrentState() ConnState {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state
}

// UpdateEndpoint changes the endpoint and forces a reconnect.
func (c *Client) UpdateEndpoint(endpoint string) {
	c.mu.Lock()
	c.endpoint = endpoint
	conn := c.conn
	c.mu.Unlock()

	if conn != nil {
		conn.Close(websocket.StatusNormalClosure, "endpoint changed")
	}
}

// UpdateAuth updates the auth token.
func (c *Client) UpdateAuth(auth string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.auth = auth
}

// Close gracefully closes the WebSocket connection.
func (c *Client) Close() {
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()

	if conn != nil {
		conn.Close(websocket.StatusNormalClosure, "client closed")
	}
}

func (c *Client) setState(s ConnState) {
	c.mu.Lock()
	c.state = s
	c.mu.Unlock()

	select {
	case c.stateCh <- s:
	default:
		// Don't block if nobody is reading
	}
}
