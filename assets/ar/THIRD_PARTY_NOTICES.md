# AR third-party notices

## MediaPipe Selfie Segmenter

`models/selfie_segmenter.tflite` is the unmodified, version-pinned Google
SelfieSegmenter square float16 model:

https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite

SHA-256: `191AC9529AE506EE0BEEFA6B2C945A172DAB9D07D1E802A290A4E4038226658B`

The official model card licenses this model under Apache License 2.0:

https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Selfie%20Segmentation.pdf

License text: `models/SELFIE_SEGMENTATION_LICENSE.txt`.
The model receives camera frames locally and produces a real person-confidence
matte. The binary contains one output channel labelled `selfie`; foreground
confidence is used directly, with soft alpha edges. No model download is needed
at camera startup. Thin hair/fingers, motion, darkness and distant people can
reduce mask accuracy, as documented in the model card.

## MediaPipe Face Landmarker

`models/face_landmarker.task` is the official MediaPipe Face Landmarker model
bundle downloaded from:

https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task

SHA-256: `64184E229B263107BC2B804C6625DB1341FF2BB731874B0BCC2FE6544E0BC9FF`

MediaPipe source and official samples are distributed under the Apache License
2.0. The model is redistributed as the unmodified model bundle explicitly
linked by Google's Face Landmarker documentation. Review Google's applicable
terms before redistributing a modified model.

MediaPipe Tasks processes camera input on-device and does not send those input
frames to Google. Google's current MediaPipe privacy notice states that Tasks
APIs send performance and utilization metrics. Any shipping host app must
disclose that metrics processing and obtain informed consent where applicable:

https://github.com/google-ai-edge/mediapipe#privacy
