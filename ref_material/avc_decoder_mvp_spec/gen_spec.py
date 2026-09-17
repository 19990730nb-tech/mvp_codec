from html import escape
import os
from pathlib import Path
import shutil
import struct
import subprocess
from textwrap import dedent

SPEC_DIR = Path(__file__).resolve().parent
ROOT_DIR = SPEC_DIR.parent


def svg_header(width, height, title, subtitle=None):
    subtitle_text = (
        f'<text x="{width // 2}" y="64" class="subtitle" '
        f'text-anchor="middle">{escape(subtitle)}</text>'
        if subtitle else ""
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <title>{escape(title)}</title>
  <rect width="100%" height="100%" fill="#ffffff"/>
  <defs>
    <marker id="arrow" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto">
      <path d="M0,0 L9,4.5 L0,9 z" fill="#263238"/>
    </marker>
    <marker id="feedbackArrow" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto">
      <path d="M0,0 L9,4.5 L0,9 z" fill="#1565c0"/>
    </marker>
    <style>
      .title {{ font: 700 26px Arial, sans-serif; fill: #111; }}
      .subtitle {{ font: 14px Arial, sans-serif; fill: #455a64; }}
      .box-title {{ font: 700 16px Arial, sans-serif; fill: #111; }}
      .body {{ font: 14px Arial, sans-serif; fill: #222; }}
      .small {{ font: 12px Arial, sans-serif; fill: #37474f; }}
      .tiny {{ font: 11px Arial, sans-serif; fill: #455a64; }}
      .external {{ fill: #fff; stroke: #607d8b; stroke-width: 1.5; rx: 10; }}
      .decoder {{ fill: #f5f7f8; stroke: #263238; stroke-width: 2; rx: 10; }}
      .reuse {{ fill: #e8f1f5; stroke: #1565c0; stroke-width: 1.8; rx: 10; }}
      .control {{ fill: #f3e5f5; stroke: #6a1b9a; stroke-width: 1.8; rx: 10; }}
      .flush {{ fill: #fff8e1; stroke: #ef6c00; stroke-width: 1.5; stroke-dasharray: 7 5; rx: 10; }}
      .disabled {{ fill: #fafafa; stroke: #9e9e9e; stroke-width: 1.2; stroke-dasharray: 6 5; rx: 10; }}
      .arrow {{ fill: none; stroke: #263238; stroke-width: 2; marker-end: url(#arrow); }}
      .feedback {{ fill: none; stroke: #1565c0; stroke-width: 1.8; marker-end: url(#feedbackArrow); }}
    </style>
  </defs>
  <text x="{width // 2}" y="36" class="title" text-anchor="middle">{escape(title)}</text>
  {subtitle_text}
'''


def box(x, y, width, height, lines, style="decoder", title=True):
    result = [f'<rect x="{x}" y="{y}" width="{width}" height="{height}" class="{style}"/>']
    start = y + 30
    for index, value in enumerate(lines):
        cls = "box-title" if title and index == 0 else "body"
        result.append(
            f'<text x="{x + width / 2}" y="{start + index * 22}" class="{cls}" '
            f'text-anchor="middle">{escape(value)}</text>'
        )
    return "".join(result)


def note(x, y, value, cls="small", anchor="middle"):
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{escape(value)}</text>'


def arrow(x1, y1, x2, y2, style="arrow"):
    return f'<path d="M{x1},{y1} L{x2},{y2}" class="{style}"/>'


def polyline(points, style="arrow"):
    path = "M" + " L".join(f"{x},{y}" for x, y in points)
    return f'<path d="{path}" class="{style}"/>'


def finish_svg(parts):
    parts.append("</svg>")
    return "".join(parts)


def write_pair(relative_stem, svg, width, height):
    svg_path = ROOT_DIR / f"{relative_stem}.svg"
    png_path = ROOT_DIR / f"{relative_stem}.png"
    svg_path.write_text(svg, encoding="utf-8", newline="\n")
    render_png(svg_path, png_path, width, height)


def render_png(svg_path, png_path, width, height):
    edge_candidates = [shutil.which("msedge"), shutil.which("microsoft-edge")]
    for env_name in ("ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"):
        root = os.environ.get(env_name)
        if root:
            edge_candidates.append(Path(root) / "Microsoft/Edge/Application/msedge.exe")
    edge = next((Path(candidate) for candidate in edge_candidates if candidate and Path(candidate).is_file()), None)
    inkscape = shutil.which("inkscape")
    try:
        import cairosvg
    except Exception:
        cairosvg = None

    attempts = []
    if edge is not None:
        attempts.append(("Microsoft Edge", lambda: subprocess.run([
            str(edge),
            "--headless",
            "--disable-gpu",
            "--hide-scrollbars",
            "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=1000",
            f"--window-size={width},{height}",
            f"--screenshot={png_path}",
            svg_path.as_uri(),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)))
    if inkscape is not None:
        attempts.append(("Inkscape", lambda: subprocess.run([
            inkscape,
            str(svg_path),
            "--export-type=png",
            f"--export-filename={png_path}",
            f"--export-width={width}",
            f"--export-height={height}",
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)))
    if cairosvg is not None:
        attempts.append(("CairoSVG", lambda: cairosvg.svg2png(
            url=str(svg_path),
            write_to=str(png_path),
            output_width=width,
            output_height=height,
        )))

    errors = []
    for name, render in attempts:
        try:
            png_path.unlink(missing_ok=True)
            render()
            validate_png(png_path, width, height)
            print(f"rasterizer: {name}")
            return
        except Exception as error:
            attempts_message = f"{name}: {error}".replace("\n", " ")[:240]
            errors.append(attempts_message)

    supported = "Microsoft Edge, Inkscape, CairoSVG"
    if not attempts:
        raise RuntimeError(f"No supported rasterizer available; supported rasterizers: {supported}")
    raise RuntimeError(f"Supported rasterizers failed ({supported}): {'; '.join(errors)}")


def validate_png(png_path, width, height):
    if not png_path.is_file() or png_path.stat().st_size == 0:
        raise RuntimeError(f"rasterizer did not create {png_path}")
    with png_path.open("rb") as stream:
        signature = stream.read(8)
        length_bytes = stream.read(4)
        chunk = stream.read(4)
        dimensions = stream.read(8)
    if signature != b"\x89PNG\r\n\x1a\n" or chunk != b"IHDR" or len(dimensions) != 8:
        raise RuntimeError(f"invalid PNG signature or IHDR in {png_path}")
    actual_width, actual_height = struct.unpack(">II", dimensions)
    if actual_width != width or actual_height != height:
        raise RuntimeError(
            f"unexpected PNG dimensions for {png_path}: "
            f"{actual_width}x{actual_height}, expected {width}x{height}"
        )


def make_root_diagram():
    width, height = 1900, 1040
    parts = [svg_header(
        width,
        height,
        "AVC Decoder MVP Canonical Data Flow",
        "Implemented ownership and transaction flow; blue arrows are commit or rolling-neighbor feedback",
    )]

    blocks = [
        (35, 150, 210, 145, ["Decoded syntax", "mode / coordinates", "A/B availability", "MVD / ref_idx / skip"], "external"),
        (285, 150, 220, 145, ["vc_mvp_dec_ctrl", "accept and latch", "DEC_NEIB to DEC_SEND", "P8 order tracking"], "control"),
        (545, 150, 255, 180, ["vc_mvp_dec_neib_top", "vc_mvp_dec_neib_adapter", "real Neighbor hierarchy", "A/B snapshot and drain"], "reuse"),
        (840, 150, 255, 180, ["vc_mvp_dec_cand", "real vc_mvp_cand_gen", "A=A1  B=B1", "C=B0 then B2", "candidate0 only"], "reuse"),
        (1115, 150, 245, 180, ["vc_mvp_dec_recon", "signed 17-bit add", "P_SKIP zero rule", "final MV and ref_idx"], "decoder"),
        (1380, 150, 255, 180, ["vc_mvp_dec_mc_adapter", "selected lane", "rdy/data held until ack", "dec_send"], "decoder"),
        (1710, 150, 160, 145, ["MC / mrg2mc", "interface", "MC acknowledgement", "mc2mrg ack"], "external"),
    ]
    for x, y, w, h, labels, style in blocks:
        parts.append(box(x, y, w, h, labels, style))

    for x1, x2, label in [
        (245, 285, "accepted"),
        (505, 545, "neib_start"),
        (800, 840, "capture"),
        (1095, 1115, "MVP"),
        (1360, 1380, "DEC_SEND"),
        (1635, 1710, "rdy / data"),
    ]:
        parts.append(arrow(x1, 220, x2, 220))
        parts.append(note((x1 + x2) / 2, 205, label, "tiny"))

    parts.append(box(585, 390, 685, 110, [
        "vc_mvp_dec_upd_adapter",
        "cur_cu_upd = mc_commit",
        "committed final MV / ref_idx / coordinates",
    ], "reuse"))
    parts.append(arrow(1710, 270, 1635, 270, "feedback"))
    parts.append(note(1672, 255, "mc2mrg ack", "tiny"))
    parts.append(polyline([(1505, 330), (1505, 360), (1270, 360), (1270, 390)], "feedback"))
    parts.append(note(1385, 350, "mc_commit", "small"))
    parts.append(polyline([(585, 445), (500, 445), (500, 355), (675, 355), (675, 330)], "feedback"))
    parts.append(note(525, 345, "cur_cu_upd / committed MV context", "tiny"))

    parts.append(box(35, 620, 1815, 125, [
        "P8 serial dependency",
        "S0 -> commit/update -> S1 -> commit/update -> S2 -> commit/update -> S3 -> commit/update",
        "next expected sub-index advances only after the preceding mc_commit",
    ], "reuse"))

    parts.append(box(35, 800, 1815, 125, [
        "Flush and drain barrier",
        "slice or mode cancellation suppresses Candidate, reconstruction, MC, and update activity",
        "physical A/B outstanding reads drain before Neighbor ready or qualified completion reopens",
    ], "flush"))
    parts.append(note(950, 970, "Phase 1: P16x16, P8x8, P_SKIP; List0 and ref_idx 0; temporal/Col, scaling, and RefList traversal inactive", "small"))
    return finish_svg(parts), width, height


def make_fig1():
    width, height = 1750, 860
    parts = [svg_header(
        width,
        height,
        "AVC Decoder MVP Hierarchy and Ownership",
        "The Decoder owns admission through MC retirement; reused Neighbor and Candidate logic remain explicit",
    )]
    parts.append(box(70, 125, 280, 170, ["vc_mvp_dec_top", "top-level Decoder", "backend and Candidate"], "control"))
    parts.append(box(430, 110, 300, 200, ["vc_mvp_dec_backend_top", "Neighbor top", "reconstruction", "MC adapter", "update adapter"], "decoder"))
    parts.append(box(810, 110, 300, 200, ["vc_mvp_dec_neib_top", "vc_mvp_dec_ctrl", "neib_adapter", "real vc_mvp_get_neib", "dec_upd_adapter"], "reuse"))
    parts.append(box(1190, 110, 250, 200, ["vc_mvp_dec_cand", "real vc_mvp_cand_gen", "AVC MED", "candidate0"], "reuse"))
    parts.append(arrow(350, 210, 430, 210))
    parts.append(arrow(730, 210, 810, 210))
    parts.append(polyline([(210, 295), (210, 345), (1315, 345), (1315, 310)], "arrow"))

    parts.append(box(85, 420, 260, 145, ["accepted syntax", "latched transaction", "MVD / ref_idx / mode"], "external"))
    parts.append(box(430, 405, 250, 175, ["DEC_NEIB", "A/B read and snapshot", "qualified Neighbor done"], "reuse"))
    parts.append(box(765, 405, 250, 175, ["Candidate capture", "spatial MVP", "cand_capture_done"], "reuse"))
    parts.append(box(1100, 405, 250, 175, ["reconstruction", "final MV", "dec_recon_start / done"], "decoder"))
    parts.append(box(1430, 405, 250, 175, ["DEC_SEND", "mrg2mc packet", "MC acknowledgement"], "decoder"))
    parts.append(arrow(345, 492, 430, 492))
    parts.append(arrow(680, 492, 765, 492))
    parts.append(arrow(1015, 492, 1100, 492))
    parts.append(arrow(1350, 492, 1430, 492))
    parts.append(box(465, 665, 570, 105, ["mc_commit", "cur_cu_upd", "rolling a_0_reg / b_0_reg / buf_reg"], "reuse"))
    parts.append(polyline([(1555, 580), (1555, 630), (1035, 630), (1035, 665)], "feedback"))
    parts.append(polyline([(465, 715), (360, 715), (360, 565), (430, 565)], "feedback"))
    parts.append(note(1290, 615, "rdy & ack -> mc_commit", "small"))
    parts.append(box(1080, 665, 310, 105, ["flush", "cancel downstream pulses", "drain A/B responses"], "flush"))
    return finish_svg(parts), width, height


def make_fig2():
    width, height = 1600, 900
    parts = [svg_header(
        width,
        height,
        "AVC P8x8 Serial Neighbor and Commit Flow",
        "Each later sub-block waits for the preceding MC commit and rolling-neighbor update",
    )]
    xs = [55, 435, 815, 1195]
    names = ["S0", "S1", "S2", "S3"]
    source = [
        ["A/B SRAM snapshot", "C uses B0/B2"],
        ["A from a_0_reg", "B/C Neighbor view"],
        ["A Neighbor view", "B/C rolling state"],
        ["A/B/C rolling view", "boundary handling"],
    ]
    for x, name, labels in zip(xs, names, source):
        parts.append(box(x, 180, 300, 210, [name, "Neighbor acquisition", *labels, "Candidate0 -> recon"], "reuse"))
    for i in range(3):
        parts.append(arrow(xs[i] + 300, 285, xs[i + 1], 285))
        parts.append(note((xs[i] + 300 + xs[i + 1]) / 2, 270, "after mc_commit", "tiny"))

    parts.append(box(125, 500, 1350, 120, [
        "MC adapter",
        "P8 lane 0, mask 3'b001, size code 1; rdy stays asserted while ack is low",
        "mc_commit = |(rdy & ack); dec_mrg2mc_cand_done is a registered one-cycle pulse",
    ], "decoder"))
    for x in [205, 585, 965, 1345]:
        parts.append(polyline([(x, 390), (x, 470), (x, 500)], "arrow"))
    parts.append(box(280, 700, 1040, 95, [
        "cur_cu_upd from mc_commit",
        "rolling a_0_reg / b_0_reg / buf_reg become visible to the next required Neighbor lookup",
    ], "reuse"))
    parts.append(polyline([(800, 620), (800, 700)], "feedback"))
    parts.append(box(60, 825, 1480, 50, [
        "flush: cancel current transaction; A/B physical read counters remain until rd_lat drain; ready and qualified Neighbor done reopen only when quiescent",
    ], "flush"))
    return finish_svg(parts), width, height


def make_fig3():
    width, height = 1750, 980
    parts = [svg_header(
        width,
        height,
        "AVC Candidate, P_SKIP, Reconstruction, and MC Mapping",
        "Phase-1 AVC uses candidate0, signed component arithmetic, and the reused mrg2mc packet interface",
    )]
    parts.append(box(45, 350, 300, 200, ["Neighbor candidates", "A = A1", "B = B1", "C = B0 then B2", "A0 masked"], "reuse"))
    parts.append(box(430, 105, 360, 220, ["Normal Inter", "MVP X/Y + MVD X/Y", "explicit signed 17-bit", "low 16 bits retained", "final MV"], "decoder"))
    parts.append(box(430, 575, 360, 235, ["P_SKIP", "top16 or left16", "or available A1/B1 is zero", "true -> final MV zero", "false -> spatial MVP", "MVD ignored; ref_idx 0"], "decoder"))
    parts.append(arrow(345, 430, 430, 215))
    parts.append(polyline([(345, 470), (380, 470), (380, 690), (430, 690)], "arrow"))

    parts.append(box(870, 310, 300, 190, ["final MV / ref_idx", "normal: low-16 result", "skip: zero or spatial MVP", "common result boundary"], "decoder"))
    parts.append(polyline([(790, 215), (830, 215), (830, 365), (870, 365)], "arrow"))
    parts.append(polyline([(790, 690), (830, 690), (830, 445), (870, 445)], "arrow"))

    parts.append(box(1230, 310, 300, 190, ["common MC adapter", "P8 -> lane 0", "P16/P_SKIP -> lane 1", "lane 2 unused", "rdy/data held stable", "until MC ack"], "decoder"))
    parts.append(arrow(1170, 405, 1230, 405))
    parts.append(box(1580, 310, 145, 190, ["retirement", "ack", "mc_commit", "done/update"], "reuse"))
    parts.append(arrow(1530, 405, 1580, 405))

    parts.append(box(80, 875, 1645, 70, [
        "Phase-1 tie-offs: NUM_REF=1, Candidate-side cur_ref_idx=0, sanitized Neighbor ref fields, temporal/Col and scaling inactive, RefList traversal inactive",
    ], "disabled"))
    return finish_svg(parts), width, height


def make_spec():
    return dedent('''
    # AVC Decoder MVP Architecture Spec v0.1

    > Status: **Phase-1 directed RTL verification for T02 and T07 is closed** against RTL baseline `3a124096f71b3a6c9ccf04fab52b48f8db8f4ed7`, using Synopsys VCS W-2024.09-SP2-2. This record does not claim full-chip, bitstream-level, formal, coverage-closure, or production signoff.

    ## 0. Source of truth and scope

    `ref_material/avc_decoder_mvp_spec/gen_spec.py` is the reproducible source of truth for this Markdown file, the canonical root diagram, and the three detailed figure pairs. It writes only beneath `ref_material/`.

    The executable hierarchy is the authority:

    ```text
    vc_mvp_dec_top
    +- vc_mvp_dec_backend_top
       +- vc_mvp_dec_neib_top
       |  +- vc_mvp_dec_ctrl
       |  +- vc_mvp_dec_neib_adapter
       |  +- real vc_mvp_get_neib hierarchy
       |  `- vc_mvp_dec_upd_adapter
       +- vc_mvp_dec_recon
       +- vc_mvp_dec_mc_adapter
    `- vc_mvp_dec_cand
       `- real vc_mvp_cand_gen
    ```

    Phase 1 supports P16x16, P8x8, and P_SKIP; List0 with one active reference and legal `ref_idx=0`. List1, temporal and Col candidates, reference traversal, scaling, encoder search, and cost selection are inactive.

    ## 1. Canonical transaction flow

    ```text
    accepted decoded syntax
      -> DEC_NEIB
      -> real Neighbor result
      -> Candidate capture
      -> reconstruction
      -> DEC_SEND
      -> decoder MC adapter
      -> reused mrg2mc interface
      -> MC acknowledgement
      -> mc_commit
      -> cur_cu_upd
      -> rolling Neighbor state
    ```

    `vc_mvp_dec_ctrl` owns the Decoder transaction state. The final MV is emitted directly by the Decoder MC adapter through the reused `mrg2mc` branch. The acknowledgement is `mc2mrg_cand_ack`; retirement is `mc_commit`; `dec_mrg2mc_cand_done` is the registered one-cycle completion pulse toward MC; `cur_cu_upd` is generated from the same accepted handshake.

    ## 2. Candidate behavior

    The real `vc_mvp_cand_gen` AVC MED path is wrapped by `vc_mvp_dec_cand`.

    - A = A1 = `neib_a[1]`.
    - B = B1 = `neib_b[1]`.
    - C = B0 when available, otherwise B2.
    - A0 is masked by `vc_mvp_dec_cand`.
    - B0 has priority when B0 and B2 are both available.
    - Candidate0 is consumed; Candidate1 is disabled.

    | Available operands | Candidate-0 result |
    |---|---|
    | none | zero |
    | A only | A1 |
    | B only | B1 |
    | C only | B0, otherwise B2 fallback |
    | A+B | signed component-wise MED(A, B, 0) |
    | A+C | signed component-wise MED(A, 0, C) |
    | B+C | signed component-wise MED(0, B, C) |
    | A+B+C | signed component-wise MED(A, B, C) |

    Candidate data is combinational during the accepted start/IDLE cycle. `vc_mvp_dec_cand` captures candidate0 on the launch edge and reports `cand_capture_done` as the handoff event. Legacy Candidate-generator `cand_blk_done` is not the Decoder data-valid event.

    Phase-1 inputs are deterministic: `NUM_REF=1`, Candidate-side `cur_ref_idx=0`, Neighbor reference fields sanitized to zero, temporal/Col and scaling paths disabled, and legal decoded reference index zero. The legacy reference-index field remains structurally present but is not used for Phase-1 traversal or remapping.

    Evidence: `src_dec_dev/vc_mvp_dec_cand.v:31-116`, `src_encoder_ref/vc_mvp_cand_gen.v:203-215`, `src_encoder_ref/vc_mvp_cand_gen.v:411-445`, `src_encoder_ref/vc_mvp_cand_gen.v:1211-1224`, `src_encoder_ref/vc_mvp_cand_gen.v:1329-1330`.

    ## 3. Reconstruction and P_SKIP

    For normal Inter, MVP X/Y and MVD X/Y are interpreted as signed 16-bit two's-complement components. Each operand is explicitly sign-extended to signed 17 bits, added independently, and retained as the low 16 bits:

    ```text
    MVP X/Y + MVD X/Y
      -> signed 17-bit component-wise addition
      -> sum_x[15:0] and sum_y[15:0]
      -> final MV = {sum_y[15:0], sum_x[15:0]}
    ```

    This is low-bit modulo retention, not saturation. Out-of-range sums produce simulation-only diagnostics; no recovery output is exposed.

    The implemented P_SKIP condition is:

    ```text
    skip_zero_motion =
        picture_top16
     || picture_left16
     || (B1 available && B1 MV == 0)
     || (A1 available && A1 MV == 0)
    ```

    When true, final MV is zero. Otherwise final MV is the spatial MVP. P_SKIP final `ref_idx` is zero and MVD is ignored. Picture-boundary flags are derived from accepted and latched CTU/CU coordinates, not live upstream coordinates.

    Evidence: `src_dec_dev/vc_mvp_dec_recon.v:23-83`, `src_dec_dev/vc_mvp_dec_neib_top.v:249-252`.

    ![Mode, Candidate, reconstruction, and MC mapping](fig3_mode_mv_derivation.svg)

    ## 4. MC interface and commit ownership

    The Decoder MC adapter reuses the existing `mrg2mc` packet shape:

    - P8 selects lane 0 with mask `3'b001` and size code 1.
    - P16 and P_SKIP select lane 1 with mask `3'b010` and size code 2.
    - Lane 2 is unused.
    - `dec_mrg2mc_cand_nb = 0`.
    - The packet contains valid, picture coordinates, two size fields, reference index, and final MV.
    - `mc2mrg_cand_ack` is the MC acknowledgement input.
    - `mc_commit = |(rdy & ack)` is the architectural retirement event.
    - `dec_mrg2mc_cand_done` is a registered one-cycle pulse after the accepted handshake.
    - `cur_cu_upd` is generated from `mc_commit` and carries final MV, reference index, and coordinates into rolling Neighbor state.

    While `mc2mrg_cand_ack` is low, `dec_mrg2mc_cand_rdy` remains asserted on the selected lane and the packet/transaction remain stable.

    Evidence: `src_dec_dev/vc_mvp_dec_mc_adapter.v:34-104`, `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54`.

    ## 5. P8 ordering and Neighbor persistence

    ```text
    S0 -> MC commit/update
       -> S1 -> MC commit/update
            -> S2 -> MC commit/update
                 -> S3 -> MC commit/update
    ```

    The next expected P8 sub-index advances only after the preceding sub-block's `mc_commit`. The resulting `cur_cu_upd` updates the rolling Neighbor state used by later sub-blocks.

    ![P8 serial Neighbor flow](fig2_p8_serial_neighbor_flow.svg)

    Evidence: `src_dec_dev/vc_mvp_dec_ctrl.v:226-233`, `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54`, `src_encoder_ref/vc_mvp_get_neib.v:994-1015`.

    ## 6. Flush and drain behavior

    Slice or mode cancellation is synchronous in the controller, Candidate wrapper, reconstruction block, and MC adapter. MC output is immediately suppressed during flush. A stale MC acknowledgement cannot retire cancelled work.

    Neighbor integration tracks physical accepted-but-not-yet-returned A/B reads. Those outstanding counters survive Decoder flush until `rd_lat` responses drain. External ready and qualified Neighbor completion remain blocked until both directions are quiescent.

    Evidence: `src_dec_dev/vc_mvp_dec_ctrl.v:157-190`, `src_dec_dev/vc_mvp_dec_cand.v:83-116`, `src_dec_dev/vc_mvp_dec_recon.v:50-83`, `src_dec_dev/vc_mvp_dec_mc_adapter.v:34-104`, `src_dec_dev/vc_mvp_dec_neib_top.v:238-324`.

    ![Overall hierarchy and ownership](fig1_avc_decoder_mvp_arch.svg)

    ## 7. Static evidence table

    | Finding | Repository evidence |
    |---|---|
    | Decoder top owns the complete path | `src_dec_dev/vc_mvp_dec_top.v:98-196` |
    | Backend owns Neighbor, reconstruction, MC, and update adapters | `src_dec_dev/vc_mvp_dec_backend_top.v:101-228` |
    | Real Neighbor hierarchy is instantiated | `src_dec_dev/vc_mvp_dec_neib_top.v:326-407` |
    | Real Candidate core is instantiated | `src_dec_dev/vc_mvp_dec_cand.v:54-80` |
    | Controller states are DEC_IDLE, DEC_NEIB, DEC_MVP, DEC_RECON, and DEC_SEND | `src_dec_dev/vc_mvp_dec_ctrl.v:56-62` |
    | MC acknowledgement retires the transaction | `src_dec_dev/vc_mvp_dec_ctrl.v:147-151`; `src_dec_dev/vc_mvp_dec_mc_adapter.v:68-83` |
    | Rolling update is handshake-qualified | `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54` |
    | Neighbor ready and completion use the drain barrier | `src_dec_dev/vc_mvp_dec_neib_top.v:242-261`, `296-324` |

    ## 8. Verification record

    Phase-1 directed RTL verification for T02 and T07 is closed against RTL baseline `3a124096f71b3a6c9ccf04fab52b48f8db8f4ed7` using Synopsys VCS W-2024.09-SP2-2.

    ### T02 standalone real Candidate

    - Normal build: PASS, 15 Candidate transactions, 396000 ps.
    - `+define+SYNTHESIS`: PASS, 15 Candidate transactions, 396000 ps.
    - Normal CASE 18 emitted exactly one expected overlapping-start `$error` diagnostic.
    - `SYNTHESIS` removed that diagnostic as intended.
    - Runtime checks covered B0-over-B2 priority, signed MED, only-A1/B1/B0/B2 selection, P8/P16, and P_SKIP spatial selection.

    ### T07 real-Candidate full pipeline

    - Normal build: PASS, 2076000 ps.
    - `+define+SYNTHESIS`: PASS, 2076000 ps.
    - Results were identical in both builds.

    | Event or request | Verified result |
    |---|---:|
    | accepted | 17 |
    | candidate | 16 |
    | recon_done | 15 |
    | transfer | 14 |
    | commit | 14 |
    | done | 14 |
    | update | 14 |
    | lane_done | `{4,10,0}` |
    | Neighbor A requests | 20 |
    | Neighbor B requests | 17 |
    | Col requests | 0 |
    | RefList requests | 0 |

    Cases A-I covered Candidate behavior, signed reconstruction, P8 serial rolling updates, P_SKIP, MC backpressure, flush cancellation, and stale-ack rejection. These are directed RTL results; this record does not claim full-chip, bitstream-level, formal, coverage-closure, or production signoff.

    ## 9. Generated artifacts

    The generator produces this file, the canonical root pair `../AVC_Decoder_Only_Data_Flow_v1.svg` and `.png`, and these detailed pairs:

    - `fig1_avc_decoder_mvp_arch.svg` and `.png`
    - `fig2_p8_serial_neighbor_flow.svg` and `.png`
    - `fig3_mode_mv_derivation.svg` and `.png`

    The retired root mode diagram and the absent `spec_assets` namespace are not generated or canonical.
    ''').strip() + "\n"


def make_readme():
    return dedent('''
    AVC Decoder MVP Architecture Spec v0.1

    Source of truth
    ---------------
    Run from the repository root:

        python ref_material/avc_decoder_mvp_spec/gen_spec.py

    The generator derives all output paths from its own repository location and writes only under ref_material/.

    PNG rasterizer fallback
    -----------------------
    Generation tries an available Microsoft Edge executable first, then Inkscape discovered through PATH, then CairoSVG when importable. Inkscape receives the SVG input, PNG output path, and requested width and height. If none is available, generation reports the supported rasterizers and stops. Every PNG is checked for a valid signature, nonzero size, and expected dimensions.

    Canonical diagram
    -----------------
    ref_material/AVC_Decoder_Only_Data_Flow_v1.svg
    ref_material/AVC_Decoder_Only_Data_Flow_v1.png

    Generated files
    ---------------
    ref_material/avc_decoder_mvp_spec/AVC_Decoder_MVP_Architecture_Spec_v0.1.md
    ref_material/avc_decoder_mvp_spec/fig1_avc_decoder_mvp_arch.svg
    ref_material/avc_decoder_mvp_spec/fig1_avc_decoder_mvp_arch.png
    ref_material/avc_decoder_mvp_spec/fig2_p8_serial_neighbor_flow.svg
    ref_material/avc_decoder_mvp_spec/fig2_p8_serial_neighbor_flow.png
    ref_material/avc_decoder_mvp_spec/fig3_mode_mv_derivation.svg
    ref_material/avc_decoder_mvp_spec/fig3_mode_mv_derivation.png

    Verification record
    -------------------
    Phase-1 directed RTL verification for T02 and T07 is closed against RTL baseline 3a124096 using Synopsys VCS W-2024.09-SP2-2. T02 passed in normal and SYNTHESIS builds with 15 Candidate transactions in 396000 ps. T07 passed in normal and SYNTHESIS builds in 2076000 ps with accepted=17, candidate=16, recon_done=15, transfer=14, commit=14, done=14, update=14, lane_done={4,10,0}, Neighbor A=20, B=17, Col=0, and RefList=0. This is directed RTL verification only; it does not claim full-chip, bitstream-level, formal, coverage-closure, or production signoff.
    ''').strip() + "\n"


def main():
    root_svg, root_w, root_h = make_root_diagram()
    write_pair("AVC_Decoder_Only_Data_Flow_v1", root_svg, root_w, root_h)

    fig1, fig1_w, fig1_h = make_fig1()
    write_pair("avc_decoder_mvp_spec/fig1_avc_decoder_mvp_arch", fig1, fig1_w, fig1_h)

    fig2, fig2_w, fig2_h = make_fig2()
    write_pair("avc_decoder_mvp_spec/fig2_p8_serial_neighbor_flow", fig2, fig2_w, fig2_h)

    fig3, fig3_w, fig3_h = make_fig3()
    write_pair("avc_decoder_mvp_spec/fig3_mode_mv_derivation", fig3, fig3_w, fig3_h)

    (SPEC_DIR / "AVC_Decoder_MVP_Architecture_Spec_v0.1.md").write_text(make_spec(), encoding="utf-8", newline="\n")
    (SPEC_DIR / "README.txt").write_text(make_readme(), encoding="utf-8", newline="\n")
    print("generated AVC Decoder MVP documentation under ref_material/")


if __name__ == "__main__":
    main()
