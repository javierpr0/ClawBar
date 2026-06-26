# claude-status-bar

App ligera para la barra de menús de macOS que muestra el estado de Claude Code de un
vistazo. Sin ventana principal, sin ícono en el Dock. Un único binario Swift que también
actúa como hook y como instalador.

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
- Reinstalar hooks · Salir.

Funciona con Claude Code en terminal, la pestaña **Code** de la app de escritorio y
**Cursor** — todos leen `~/.claude/settings.json`, donde el instalador escribe los hooks.

## Instalar / actualizar

```bash
./install.sh
```

Esto compila, copia el binario a `~/.claude-status-bar/bin/`, escribe los hooks en
`~/.claude/settings.json` (idempotente, respeta tus hooks existentes) e instala un
LaunchAgent para arrancar la app al iniciar sesión. Reinicia las sesiones de Claude Code
abiertas para que tomen los hooks. Vuelve a ejecutarlo para actualizar.

## Desinstalar

```bash
.build/release/claude-status-bar uninstall
```

Quita los hooks y el arranque automático.

## Cómo funciona

Los hooks de Claude Code (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`,
`Stop`, `SessionStart/End`) ejecutan `claude-status-bar hook <Event>`, que lee el JSON del
evento por stdin y actualiza `~/.claude-status-bar/state.json` (con `flock`). La app observa
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
