# Kit gaps found while building the Pointroo mockups

Each gap names the stand-in the mockups use today. The app draws none of these itself. G0 to G10 come from the UX spec
(section 7). G11 and up are new, found while building.

| # | Gap | Needed by | Stand-in in the mockups |
|---|---|---|---|
| G0 | Brand layer `brands/pointroo.css` and `pointroo` in `BRAND_NAMES` | every screen | `oneroo` brand (spec question 1) |
| G1 | RooNoticeCard: card for an app-owned floating panel (surface, radius, shadow, head, media row, actions, "+N", hover pauses the timer) | notice (done with images, question) | `parts/FloatingSurface.vue` (kit tokens only); RooToast for the text-only done notice |
| G2 | Icons `mic`, `reply`, `message-circle-question`, `monitor` | pill, notice, set up | `circle-help`, `send`, `image` |
| G3 | RooStateMark state `recording` (the one red dot that may pulse) | pill | RooStateMark `err` with the word "Recording" hidden visually |
| G4 | RooThumb: image tile, fixed aspect, number chip, click or Space opens the full image, alt text required, list-row tile size | list rows, crops, notice | RooIcon `image` in the row tile; crop rows are RooListRow with a RooChip number |
| G5 | Image pair "Before" / "Screen now" | notice, detail | two RooListRow rows with an image icon (detail); text only (RooToast) |
| G6 | HUD surface for a tiny always-on-top strip (height 44, radius, shadow, drag area) | recording pill | `parts/FloatingSurface.vue` |
| G7 | Group head for a content list (RooSidebarGroup is for sidebars) | list groups | RooSidebarGroup `placement="sidebar"` |
| G8 | Media frame: muted looping video with poster and pause button, still under reduced motion | How it works | RooHowItWorks default example rows only (no loop) |
| G9 | RooMeta is 11px, under the 12px family floor | meta text | 12px muted text through RooListRow subtitle |
| G10 | RooSwitcher inline with a visible heading line | picker | a heading above an open RooSwitcher; `label` is aria only |

## New gaps from the build

| # | Gap | Where | What the mockup does |
|---|---|---|---|
| G11 | `@roo/kit/static.css` has `.roo-static-card` (surface, card radius, card shadow), but an app that uses the real kit CSS does not get it. There is no kit class or component for "a floating surface" in app code | pill, notices, menu bar menu | `parts/FloatingSurface.vue` copies the three declarations with tokens |
| G12 | RooSwitcher number keys are Cmd+1 to 9 (`shortcuts`), the picker needs plain 1 to 9 because the panel has no other input | picker | `shortcuts` on, so rows show a Cmd digit; Swift must handle plain digits |
| G13 | Kit style `:global(.roo-force-reduced) .roo-icon-button-fill, :global([data-motion='still']) .roo-icon-button-fill` in RooIconButton.vue compiles (Vue 3.5.46 here) to `.roo-force-reduced, [data-motion='still'] { display: none }`, which hides the whole page in any still-motion shell (the family mockups shell is one). FIXED in the kit (oneroo 39f5c9f3: each selector is now one `:global(...)`), vendored from oneroo b83e84b5 | every frame with the mockups shell | None needed now. The workaround in `ui/scripts/mockups.mjs` was removed |
| G14 | No window-button (traffic light) stand-in for review frames. RooBar leaves a 92px inset but nothing draws the buttons | main window frames | `parts/TrafficLights.vue`, three neutral circles on kit tokens |
| G15 | RooSplit sheet has no visible close or back control, only Esc | narrow main window (detail as a sheet) | none; the frame shows the sheet as it is |
| G16 | No native menu (NSMenu) mock part | menu bar menu | RooListRow rows with RooKbd on a floating surface; titles as RooBarChip |
| G17 | RooStateMark has no way to hide its word while keeping it for screen readers | pill dot | a scoped rule hides `.roo-state-mark-label` in the pill; a prop (`hideLabel`) would be cleaner |
| G18 | RooLiveDot always shows its word, so a sidebar row cannot show only the dot (spec: word as tooltip only) | sidebar rows | the word shows next to the dot |
| G19 | RooInput has no `hideLabel` (RooSelect has); a visible label cannot be skipped | port row, question input | `aria-label` and no `label` prop |
| G20 | No project tile: a one-click choice with a letter tile, a name, a "Suggested" mark, a live dot and a key (design D2, A to F) | item detail, queue list, pill picker | `parts/ProjectTiles.vue`: RooButton (secondary, the chosen one primary) holding RooLetterTile, RooChip, RooLiveDot, RooKbd; "More" is a RooButton that opens a RooSwitcher |
| G21 | RooChipGroup chips cannot be clicked or marked chosen (no `interactive`, no `selected`), so it cannot be a filter row | narrow window project filter (D) | RooChipGroup with the chosen chip in tone `accent`; the real row needs interactive chips |
| G22 | RooCountdown is mm:ss from an absolute end time, with no seconds-only form and no way to sit on a tile | pill picker auto (F) | RooCountdown in a line above the tiles, its end time pushed forward every half second so the still frame reads 00:03 |
| G23 | RooToast has one `actionLabel` plus Undo. The done notice needs two actions (Looks good, Reply) | done notice (H) | Undo button relabelled "Reply" through `undoLabel`, plus `actionLabel="Looks good"` |
| G24 | RooToastStack is placed on the screen, not inside a frame, so a toast cannot be shown inside a window frame | main window just sent (A, K) | one RooToast placed with `position: absolute` and space tokens inside the frame |
| G25 | RooLiveDot always shows its word (see G18), so a tile cannot show only the dot | project tiles | large tiles show "Live"; small tiles and list chips leave the dot out |

## Checked against the refreshed kit (K2)

Still open after the refresh (the kit has no part for them): G1, G3, G4, G5, G6, G7, G8, G9, G10, G11, G12, G15, G17, G18, G19, G20, G21,
G22, G23, G24, G25. G14 and G16 are mock-only. G13 is fixed. The refresh brought KPI note, neutral change tone, person chip, compact table
meter, chart area fill, RooDialog `iconTone`, rule row lead word width, focus-coloured field border and the single meter readout; none of
these is a part Pointroo draws, so nothing moved because of them.

Changes from the check:
- G2: the kit icon `host` draws a monitor, so `monitor` is covered. `mic`, `reply` and `message-circle-question` are still missing.
- G4 now also covers the places the app draws an image by hand: `parts/ItemList.vue` (112 by 72 crop tile with a count chip),
  `parts/ItemDetail.vue` (hero image, crop strip buttons, frame strip buttons) and `parts/FloatNotice.vue` (Before and Now tiles).
  Ask: RooThumb with a fixed aspect, a number chip, a pressed state and a large size for list rows. The count and the Before and Now tags are
  RooChip now.
- G3 and G17 apply to `parts/FloatPill.vue` (the 10px red dot with a hidden "Recording" word).
- G21 applies to `parts/MainWindow.vue` (the project filter row is RooChip pills, an overflow RooMenu and our own "+N").

| # | Gap | Where | What the app does |
|---|---|---|---|
| G26 | No callout for a short result note with a tinted fill (RooStateCard has a surface fill and border, so it reads as another card) | `parts/ItemDetail.vue` agent note | own markup on `--roo-ok-bg` with a RooIcon check |
| G27 | No list row with a large leading image and a two-line clamped title (RooListRow tile is one icon box, title is one line) | `parts/ItemList.vue` queue rows | own row on kit tokens, with RooStateMark and RooProgressLine inside |
| G28 | No log viewer: wrapping mono lines, role log, scrolls to the newest line (RooCodeBlock scrolls sideways and has no log role) | `parts/SettingsScreen.vue` Auto-start log | own scroll box on kit tokens |
