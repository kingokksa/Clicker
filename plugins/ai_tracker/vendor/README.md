# Bundled inference assets

These files are compiled into the installer by `windows/CMakeLists.txt` and land
next to the executable under `data/plugins/ai_tracker/`. Nothing here is
downloaded at runtime.

| File | Size | Upstream | License |
| --- | --- | --- | --- |
| `onnxruntime.dll` | 12.4 MB | Microsoft ONNX Runtime 1.21.0, `onnxruntime-win-x64-1.21.0.zip` | MIT |
| `models/ocr_det.onnx` | 4.53 MB | PP-OCRv4 text detection, `SWHL/RapidOCR` → `PP-OCRv4/ch_PP-OCRv4_det_infer.onnx` | Apache-2.0 |
| `models/ocr_rec.onnx` | 10.35 MB | PP-OCRv4 text recognition (Chinese + English), same repo → `ch_PP-OCRv4_rec_infer.onnx` | Apache-2.0 |
| `models/ocr_keys.txt` | 26 KB | `PaddlePaddle/PaddleOCR` → `ppocr/utils/ppocr_keys_v1.txt`, 6623 entries | Apache-2.0 |
| `models/detector.onnx` | 3.60 MB | YOLOX-Nano (`yolox_n.onnx`), `LibreYOLO/libreyolo-web` — decoded export of the Megvii YOLOX-Nano weights | Apache-2.0 |

## Why YOLOX-Nano instead of YOLO11n

The previously downloaded `yolov11n.onnx` is Ultralytics **AGPL-3.0**. Shipping it
inside a closed-source installer is redistribution, which the AGPL only permits
if the whole application is released under the AGPL or an Ultralytics Enterprise
License is purchased. YOLOX-Nano is Apache-2.0 and 2.9x smaller.

## Model I/O contracts (verified offline with onnxruntime 1.30.0)

`models/detector.onnx`

- input `images` `[1,3,416,416]` float32, RGB, `/255`, no mean/std normalization
- output `output` `[1,3549,85]` — 3549 = 52²+26²+13² (strides 8/16/32)
- **already decoded in-graph**: `cx, cy, w, h` are in 416x416 input pixels,
  `obj` and the 80 class scores are already sigmoid-activated
- `score = obj * max(cls)`; no letterbox grid/exp decoding is needed
- COCO 80 classes — this is a generic object detector, not a UI-element detector

`models/ocr_det.onnx`

- input `x` `[N,3,H,W]`, H and W must be multiples of 32
- output `sigmoid_0.tmp_0` `[N,1,H,W]` probability map
- preprocessing: RGB, `/255`, mean `[0.485,0.456,0.406]`, std `[0.229,0.224,0.225]`
- postprocessing: threshold 0.3 → connected components → drop boxes below
  `box_threshold` 0.6 → unclip by `area * 1.8 / perimeter`

`models/ocr_rec.onnx`

- input `x` `[N,3,48,W]` — height is fixed at 48, width is dynamic
- output `softmax_11.tmp_0` `[N,W/4,6625]` — already softmax-activated
- preprocessing: RGB, `/255`, `(x-0.5)/0.5`
- decode: per-timestep argmax, collapse repeats, drop index 0;
  `1..6623` → `ocr_keys.txt` line `k-1`, `6624` → space
