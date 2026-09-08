# Third-Party Notices

Driftless-NoMore404 is an independent, unofficial integration. These notices
identify external projects with which it interoperates; they do not imply that
their maintainers sponsor, endorse, support, or are affiliated with this
project.

## Distribution boundary

This project does not contain or redistribute:

- Hermes Agent or Hermes Desktop source or binaries;
- llama.cpp source or binaries;
- GGUF or other model weights;
- chat-template files copied from an upstream project; or
- Hermes, Nous Research, llama.cpp, or ggml-org logos and brand artwork.

The file `vendor/llama.cpp.lock` records the upstream repository, release,
revision, official Linux asset names, and SHA-256 digests used for
compatibility testing and the optional setup download. Despite its directory
name, it is not vendored software.

If a future release adds any third-party source, binary, model, template, or
asset, its license and attribution requirements must be reviewed before that
release. This file must then be updated and the required license text shipped
with the copied material.

## Hermes Agent

Project: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)

Copyright notice from upstream:

```text
Copyright (c) 2025 Nous Research
```

Hermes Agent is offered under the MIT License. The authoritative upstream text
is in its [LICENSE](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE).
The MIT License requires its copyright and permission notice to remain in all
copies or substantial portions of the software.

Driftless-NoMore404 does not copy Hermes Agent. It relies on a separately installed
Hermes instance and its documented support for custom OpenAI-compatible model
endpoints. The user remains responsible for installing, updating, configuring,
and licensing Hermes.

## llama.cpp

Project: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)

Copyright notice from upstream:

```text
Copyright (c) 2023-2026 The ggml authors
```

llama.cpp is offered under the MIT License. The authoritative upstream text is
in its [LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE). The
MIT License requires its copyright and permission notice to remain in all
copies or substantial portions of the software.

Driftless-NoMore404 does not copy or redistribute llama.cpp in this repository.
Its wrapper can execute a compatible `llama-server` supplied by the user.
Alternatively, the explicit `setup` or `install-runtime` flow downloads one
fixed official ggml-org Linux release asset directly from GitHub, verifies the
asset against the digest recorded in `vendor/llama.cpp.lock`, and retains the
archive's `LICENSE` beside the installed `llama-server` and
`llama-fit-params` executables. The latter is used for a metadata-based memory
projection before setup attempts to load model tensors. The runtime is stored
in the user's XDG data directory and is not silently updated or removed.

The user remains responsible for choosing whether that portable CPU/Vulkan
build is appropriate for their operating system and hardware and for complying
with its complete dependency notices. An independently installed build remains
supported. Prebuilt or accelerator-enabled packages may contain components
with terms in addition to llama.cpp's top-level MIT License.

## Model weights and model repositories

llama.cpp's MIT License does not license the models it can load. GGUF is a file
format, not a license, and conversion or quantization does not replace the
source model's terms.

No model is included or downloaded by Driftless-NoMore404. Before using a model,
review its authoritative model card, license, acceptable-use terms, source
provenance, and any terms attached to the particular quantized artifact. Keep a
record of the exact repository, filename, revision, and checksum used.

## Names, marks, and artwork

“Hermes Agent,” “Hermes Desktop,” and “Nous Research” are used only to identify
the upstream product with which this project interoperates. Its MIT software
license should not be treated as permission to imply endorsement or to adopt
upstream product identity. Driftless-NoMore404 therefore uses its own name and
includes no Nous Research or Hermes artwork.

The ggml-org project publishes separate
[llama.cpp brand-usage terms](https://github.com/ggml-org/llama.brand/blob/master/BRAND-USAGE.md).
Those terms permit nominative identification within their stated scope, require
source attribution for brand assets, and prohibit uses that imply sponsorship,
endorsement, or affiliation. Driftless-NoMore404 uses the text “llama.cpp” only to
describe interoperability and includes no llama.cpp brand assets.

All third-party names and marks remain subject to the rights of their respective
owners. No trademark ownership or registration status is asserted here.

## No upstream support

Report problems in Driftless-NoMore404's launcher, unit files, or documentation to
this project. Report independently reproduced Hermes Agent issues to the Hermes
Agent project and llama.cpp server issues to the llama.cpp project. Do not ask
either upstream project to support this project as though it were an
official distribution.
