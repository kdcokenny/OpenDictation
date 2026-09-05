# Third-party notices

Open Dictation uses the following third-party code and model artifacts. Parakeet weights download separately when the user requests a model. Builds bundle Whisper Tiny; the app can download other Whisper models.

## FluidAudio

- Project: [FluidAudio](https://github.com/FluidInference/FluidAudio)
- Version: 0.15.6
- Publisher: FluidInference
- License: [Apache License 2.0](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/LICENSE)

Open Dictation uses FluidAudio to load and run the Parakeet Core ML models.

## NVIDIA Parakeet TDT 0.6B v2

- Original model: [NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- Creator: NVIDIA
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Core ML conversion: [FluidInference/parakeet-tdt-0.6b-v2-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
- Changes: FluidInference converted the original model for Core ML. Open Dictation downloads and uses that converted artifact without modifying its weights.

## NVIDIA Parakeet TDT 0.6B v3

- Original model: [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- Creator: NVIDIA
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Core ML conversion: [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- Changes: FluidInference converted the original model for Core ML. Open Dictation downloads and uses that converted artifact without modifying its weights.

## whisper.cpp and Whisper

- Runtime: [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- Runtime copyright: Georgi Gerganov and whisper.cpp contributors
- Runtime license: [MIT License](https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)
- Original model and code: [OpenAI Whisper](https://github.com/openai/whisper)
- Original copyright: OpenAI
- Original license: [MIT License](https://github.com/openai/whisper/blob/main/LICENSE)
- Converted model artifacts: [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)

Open Dictation uses the MIT-licensed whisper.cpp library and converted Whisper weights.
