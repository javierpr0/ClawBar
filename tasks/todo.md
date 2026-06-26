# Plan: claude-status-bar (macOS menu bar para Claude Code)

## Complejidad: Complejo

## Arquitectura
- 1 binario Swift, 3 modos: app (menu bar), `hook <Event>` (escribe estado), `install`.
- Hooks de Claude Code escriben `~/.claude-status-bar/state.json` (flock). App lo observa por mtime.
- `.accessory` => sin Dock, sin ventana. Sin .app bundle necesario.
- Hooks user-level en `~/.claude/settings.json` => cubre terminal + app escritorio (Code) + Cursor.

## Tareas
- [x] Verificar toolchain Swift + traer docs hooks
- [x] Package.swift (SwiftPM executable)
- [x] Core.swift: State/Store(flock), Hook, Install, Anim, labels
- [x] main.swift: AppDelegate, NSStatusItem, menú, timer, animación, sonido
- [x] Mapeo eventos -> estado (UserPromptSubmit/PreToolUse/PostToolUse/Notification/Stop)
- [x] Estilos animación: spark / terminal / crab
- [x] Color ícono: Naranja / Sistema; amarillo en espera
- [x] Temporizador on/off; sonido suave en turnos > 1 min
- [x] Multi-sesión: detectar/listar/fijar sesión activa
- [x] install/update: copia binario, hooks idempotentes, LaunchAgent
- [x] install.sh + README
- [x] Build release + smoke test hook->state->render

## Ampliación (todas las features del roadmap)
- [x] #2 modelo + carpeta en el menú
- [x] #4 tokens/costo desde transcript_path (.jsonl)
- [x] #6 contador de herramientas por turno
- [x] #7 notificación nativa de permiso (osascript) + toggle
- [x] #8 badges [plan]/[max] (permission_mode + effort)
- [x] #9 cliente en tooltip/header
- [x] #10 historial del día (turnos/total/más largo)
- [x] #11 ventana de Preferencias
- [x] #12 bundle.sh -> .app (Sparkle/firma diferido)
- [x] #13 scaffold de plugin (.claude-plugin + hooks.json)

## Review
- Build release OK (Swift 6.3). Smoke test: hook->state->stop verificado; multi-sesión (s1/s2) OK.
- Rama sonido (turno >60s -> soundSeq++) verificada con turnStart en el pasado.
- GUI arranca como .accessory sin crash; sin Dock, sin ventana.
- install: binario en ~/.claude-status-bar/bin, 7 hooks idempotentes en ~/.claude/settings.json,
  LaunchAgent cargado y corriendo (pid verificado).
- "Unload failed: 5" en primer install = unload de agente no cargado, inofensivo.
- Pendiente del usuario: reiniciar sesiones de Claude Code abiertas para que tomen los hooks.
