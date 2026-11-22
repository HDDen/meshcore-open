# Quick actions

Open the widgets button before the battery indicator in the main, channel or
contact header. **Configure** opens **Modification settings → General → Widget
settings**, where each action can be shown, hidden and reordered independently.
The three header switches control where the panel button appears.

## Header display

In **Widget settings → Header button**, choose **Icon** or **Noise level**.
**Noise level** is selected by default and shows the current noise floor in dBm instead of the widgets icon;
pressing it still opens the quick-actions panel. **Extra hops** is reserved and
cannot yet be selected.

Selecting a live display reveals **Refresh interval** below the selector.
The slider has seven steps: 0.5, 1, 2, 3, 5, 7 and 10 seconds. Ten seconds is the
default. The app retains each live display's interval independently when you
switch modes. This preference applies only to header buttons; the Noise floor
widget inside the panel continues to poll once per second.

Header polling requires a visible header on the current route and a ready
node. On Android and iOS it continues while the app is visible but unfocused
(`inactive`), including Android split screen/floating windows. It pauses only
when the app is actually hidden/backgrounded (`hidden`/`paused`) or detached.
Windows, Linux and macOS have no app-lifecycle pause policy for this header:
losing window focus does not stop its queries. Web retains its existing
visibility policy.

On every platform, hiding the header, covering its route (including opening
the quick-actions panel), choosing Icon or losing the connection still stops
header queries. Returning to a visible, allowed header resumes its configured
cadence. Unsupported statistics show a dash and do not send queries.

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

## Open related settings

Hold a quick-action tile on touch devices, or right-click it on desktop:

| Quick action | Destination |
| --- | --- |
| Adaptive TX power | Modification settings, Adaptive TX power block |
| Retries | Settings → App settings, minimum-hop/repeater retry block |
| Companion proxy, TCP proxy, BLE proxy | Modification settings, companion proxy block |

When companion proxy access is not licensed, the proxy shortcuts open license
management through the private module. A shortcut remains usable when its normal
toggle is unavailable (for example adaptive TX power while minimum-hop retries
are off). The settings gesture never toggles the feature itself. The quick-actions
panel closes and its radio polling stops before navigation. While an action is
already being applied, settings gestures wait for that action to finish.

Navigation scrolls once to a stable anchor, including sections not yet built by
the lazy list. Changing settings afterwards does not scroll the page back.
