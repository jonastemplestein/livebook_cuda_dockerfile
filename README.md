# Dockerfile to deploy a Livebook instance with CUDA GPU acceleration

The file uses the official Elixir base images from [the docker hub](https://hub.docker.com/r/hexpm/elixir/tags?page=1). You can install any combination of Elixir version, Erlang version and operating system that is available there. Just change the ARGS at the top of the Dockerfile accordingly. That said, I've only tested the CUDA installation on Ubuntu 22.04 Jammy Jellyfish.

Livebook data, as well as bumblebee and mix caches will be stored in /data, so you probably want to mount a persistent volume there.

I've pieced the Dockerfile together from the following places:

- [Chris McCord's gist with a bumblebee Phoenix demo running on fly.io GPUs](https://gist.github.com/chrismccord/59a5e81f144a4dfb4bf0a8c3f2673131)
- [The livebook Dockerfile](https://github.com/livebook-dev/livebook/blob/main/Dockerfile) (and [script to publish official Docker images](https://github.com/livebook-dev/livebook/blob/main/docker/build_and_push.sh))
- [Fly.io GPU quickstart](https://fly.io/docs/gpus/gpu-quickstart/)
- [Guide to deploying livebook on Fly](https://fly.io/docs/app-guides/livebook/)

I've basically taken the livebook Dockerfile and updated the OS version and CUDA version as per Chris' gist. Then I've added the ability to select a specific livebook version to deploy. This is helpful because I wanted to be able to deploy my own branch.

I've included a `fly.toml` file that makes it easy to host on fly.io.

## How can I deploy this?

You can deploy this anywhere Docker containers are deployed. Just make sure you can access port 8080.

Or use the included `fly.toml` to deploy to fly.io. Just make sure to adjust the app name. And be aware that GPU instances are currently not in public availability, yet.

In that case I used the following command to launch the instance:

```fly deploy --vm-gpu-kind a100-pcie-40gb --volume-initial-size 100```

## How do I know it's all working?

Follow [these instructions](https://hexdocs.pm/bumblebee/llama.html) to get 7B Lllama 2 running in livebook. But make sure to replace `client: :host` with `client: :cuda`. You should then see a bunch of CUDA related output as the serving is being generated.

You'll also notice it being massively faster than when doing CPU inference.

## How can I password protect my livebook?

Set the `LIVEBOOK_PASSWORD` env var. Either in the Dockerfile in the second stage or with your hosting provider, who often expose a mechanism for this.
