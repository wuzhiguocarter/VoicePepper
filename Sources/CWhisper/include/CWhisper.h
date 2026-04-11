// CWhisper.h - Public umbrella header for CWhisper Swift module
// Exposes the whisper.cpp C API (system install via `brew install whisper-cpp`)

#pragma once

// ggml must be included first - whisper.h depends on it
// Headers are installed by Homebrew whisper-cpp formula
#include "ggml.h"
#include "ggml-cpu.h"
#include "ggml-backend.h"   // ggml_backend_load_all()
#include "whisper.h"
