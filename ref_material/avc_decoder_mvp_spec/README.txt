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
