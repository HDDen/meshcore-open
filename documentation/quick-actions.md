# Quick actions

Open the widgets button before the battery indicator in the main, channel or
contact header. **Configure** opens **Modification settings → General → Widget
settings**, where each action can be shown, hidden and reordered independently.
The three header switches control where the panel button appears.

## Live radio widgets

- **Noise floor** shows the latest radio noise reading in dBm. Pressing it
  opens **Radio statistics**. Firmware must support companion radio statistics;
  otherwise the widget is dimmed and cannot be pressed.
- **Radio TX power** shows the current radio-module power in dBm, including a
  temporary adaptive TX power increase. Pressing it opens the same radio
  parameters dialog as device settings.

Each enabled live widget requests its reading when the panel opens and then
once per second while the panel is visible and the node session is ready.
Hidden widgets do not request data. Closing with Close, back or the outside
barrier, opening Configure, following an action, covering the panel with
another route, backgrounding the app or losing the connection stops the
panel's queries. Polling resumes when the panel is visible and ready again.
The panel does not change the application's other radio-statistics polling.

A dash is shown until a reading is available. A slow or failed request does not
queue overlapping reads; each type waits for its previous request to finish.
TX power polling reads a SELF_INFO snapshot and does not rewrite settings or
restart the connection handshake. Widget sizes and labels follow app DPI.
