# ClawBar

App ligera para la barra de menús de macOS que muestra el estado de Claude Code de un
vistazo. Sin ventana principal, sin ícono en el Dock. Un único binario Swift (`clawbar`) que
también actúa como hook y como instalador. MIT.

## Qué muestra

- Ícono animado mientras Claude piensa o ejecuta una herramienta.
- Etiqueta corta de la herramienta: `Leyendo`, `Editando`, `Ejecutando`, `Buscando`…
- Indicador **amarillo** solo cuando Claude espera tu permiso (un `idle_prompt`
  no lo dispara: vuelve al ícono normal).
- Temporizador del turno actual (`m:ss`).
- Vuelve al ícono normal cuando Claude está inactivo o terminó.
- Sonido de finalización suave (chime embebido) para turnos de más de 1 minuto.

## Menú

- Mostrar / ocultar el temporizador.
- Sonido suave al terminar turnos de más de 1 minuto.
- Estilo de animación: **Spark**, **Terminal**, **Crab**.
- Color del ícono: **Naranja** o **Sistema**.
- **Sesiones**: lista las sesiones activas y permite fijar cuál sigue el ícono
  (o dejarlo en automático = la más reciente). Sigue una sesión a la vez pero
  detecta varias. Clic en una sesión la fija **y trae su app al frente**
  (Terminal/iTerm/VS Code/Cursor/Claude).
- **Notificar permisos**: banner nativo de macOS cuando Claude pide permiso.
- **Preferencias…**: ventana con los mismos ajustes (⌘,).
- Reinstalar hooks · Buscar actualizaciones · Salir.

El menú también muestra, para la sesión activa: **modelo** (`Opus 4.8`) con badges
`[plan]` / `[max]` (de `permission_mode` + `effort`), **carpeta**, **herramientas del
turno** (`Leyendo×2, Editando×1`), **tokens** del transcript (`↑ entrada / ↓ salida`,
cache, y costo aproximado), e **historial del día** (turnos · total · más largo).

Funciona con Claude Code en terminal, la pestaña **Code** de la app de escritorio y
**Cursor** — todos leen `~/.claude/settings.json`, donde el instalador escribe los hooks.

## Instalar / actualizar

```bash
./install.sh
```

Esto compila, copia el binario a `~/.clawbar/bin/`, escribe los hooks en
`~/.claude/settings.json` (idempotente, respeta tus hooks existentes) e instala un
LaunchAgent para arrancar la app al iniciar sesión. Reinicia las sesiones de Claude Code
abiertas para que tomen los hooks. Vuelve a ejecutarlo para actualizar.

## Desinstalar

```bash
.build/release/clawbar uninstall
```

Quita los hooks y el arranque automático.

## Empaquetar como .app

```bash
./bundle.sh   # genera ClawBar.app (LSUIElement, menu-bar agent)
```

Produce un `.app` de doble clic (sin firmar: en otra Mac, abrir con clic derecho →
Abrir la primera vez). La distribución firmada/notarizada con auto-update silencioso
(Sparkle) queda pendiente.

## Releases automáticos

Al hacer push de un tag `v*`, el workflow `.github/workflows/release.yml` compila,
empaqueta `ClawBar.app` (con ícono), lo zipea y publica un GitHub Release con el `.zip` +
el binario. El tag también fija la versión del binario (`v1.2.0` → `VERSION = "1.2.0"`).

Para cortar una versión, un comando:

```bash
./release.sh 1.0.1   # bumpea VERSION, commitea, taggea y pushea -> CI publica el release
```

El script valida la versión (`X.Y.Z`), exige árbol git limpio, rechaza tags repetidos y
detecta solo el remote/rama.

## Buscar actualizaciones

ClawBar consulta GitHub Releases (`javierpr0/ClawBar`): una vez al día en silencio y
manualmente desde el menú. Si hay un tag más nuevo que la versión instalada, el menú
muestra **⬆ Actualización vX disponible** y abre la página de descarga. Sin certificado
ni hosting extra.

## Como plugin de Claude Code

`.claude-plugin/plugin.json` + `hooks/hooks.json` dejan el proyecto listo para
instalarse como plugin (los hooks apuntan a `~/.clawbar/bin/clawbar`).
Requiere que el binario esté instalado antes (`./install.sh`).

## Sobre el costo de tokens

El costo es **aproximado**: precios por millón de tokens codificados en el binario
(Opus 15/75, Sonnet 3/15, Haiku 1/5; cache read ×0.1, write ×1.25). Pueden cambiar.
Los conteos de tokens sí son exactos (leídos del `transcript_path`).

## Privacidad

ClawBar es local. No envía tu actividad a ningún lado. Lee tu `transcript_path` **en
disco** solo para contar tokens del turno y todo el estado vive en `~/.clawbar/state.json`.
La única salida a red es el chequeo de actualizaciones contra la API pública de GitHub
Releases (1×/día y al pulsar "Buscar actualizaciones"); las notificaciones de permiso usan
`osascript` local. Sin telemetría, sin analytics, sin cuentas.

## Primer arranque

Si abres `ClawBar.app` y los hooks aún no están configurados, la app ofrece instalarlos
(hooks + arranque automático) con un clic — no necesitas la terminal. Desde el menú puedes
**Reinstalar hooks** o **Desinstalar ClawBar** cuando quieras.

## Cómo funciona

Los hooks de Claude Code (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`,
`Stop`, `SessionStart/End`) ejecutan `clawbar hook <Event>`, que lee el JSON del
evento por stdin y actualiza `~/.clawbar/state.json` (con `flock`). La app observa
ese archivo por mtime y redibuja el título de la barra. Los hooks son `async`, así que no
añaden latencia a Claude.

## Créditos

Los iconos (spark de Claude, frames spark, crab) y el sonido de finalización provienen de
[m1ckc3s/claude-status-bar](https://github.com/m1ckc3s/claude-status-bar) (MIT,
© 2026 Mick Cesanek).

## Limitaciones conocidas

- Una terminal cerrada a la fuerza (sin `SessionEnd`) deja su sesión "ocupada" hasta que
  expira a las 6 h; una sesión más nueva toma el ícono mientras tanto.
- Cursor y VS Code reportan el mismo `TERM_PROGRAM`; se distinguen por bundle id cuando está
  disponible.
