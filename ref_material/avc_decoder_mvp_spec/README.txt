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

Verification limitation
-----------------------
The documentation is statically aligned to baseline 3a124096. T02 standalone real-Candidate and T07 real-Candidate full-pipeline execution are pending execution on a capable VCS host; this documentation does not claim their PASS or closure.
