# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path
import tomllib


PROJECT_ROOT = Path.cwd()
with open(PROJECT_ROOT / "pyproject.toml", "rb") as f:
    APP_VERSION = tomllib.load(f).get("project", {}).get("version", "2.1.0")


a = Analysis(
    ['cbNP.py'],
    pathex=[],
    binaries=[],
    datas=[('assets/logo.png', './'), ('mediaremote_adapter', 'mediaremote_adapter')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='cbNP',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['cbNP-icon.icns'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='cbNP',
)
app = BUNDLE(
    coll,
    name='cbNP.app',
    icon='assets/logo.png',
    bundle_identifier=None,
    info_plist={
        'LSUIElement': True,
        'LSBackgroundOnly': True,
        'NSUIElement': True,
        'CFBundleShortVersionString': APP_VERSION,
    },
)
