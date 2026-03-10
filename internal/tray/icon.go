package tray

import _ "embed"

// logo.png is the full-color application icon (32x32), used as default artwork fallback.
//
//go:embed logo.png
var iconData []byte

// logo_template.png is a black-on-transparent music note silhouette (32x32),
// used as the menu bar icon via SetTemplateIcon for proper dark/light mode support.
//
//go:embed logo_template.png
var templateIconData []byte

// IconData returns the embedded full-color application icon (for default artwork, etc.).
func IconData() []byte {
	return iconData
}

// TemplateIconData returns the embedded template icon (black silhouette on transparent).
func TemplateIconData() []byte {
	return templateIconData
}
