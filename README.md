# Create a Docker image by hand

When I started with docker my intuitive idea of what an image is was:
*An image is a blue print of a container. It is similar to a stopped VM image.*

Later I read that an image is a layered file system. If you define an image via
a `Dockerfile` the `FROM` command states the base layer and each `COPY`, `ADD`, or `RUN`
defines a new layer. Commands as `EXPOSE` or `ENTRYPOINT` define some meta data that can be used to start an image.

Therefore, I understood that *an image consists of a layered file system and
a set of meta data*.
However, for me this concept seemed to be very abstract. Therefore, I thought  tha I want to create my own image manually.

Hence, I will now create a docker image with a Dockerfile, analyse it and afterwards create my own docker image manually.

In the resulting image I want to know each little piece and all aspects of it should fit into my brain. Therefore, I don't want to use a common base image as `ubuntu`, `debian`,
or `alpine` (even if it's smaller than the other images it already contains ~500 files).
I will create a minimal image that uses no pre-build base image. There are multiple different
articles about this topic (for example [this](https://linuxhint.com/create_docker_image_from_scratch/)).
Therefore, I will just summarise the important aspects.

## Minimal Image
I want to create an image that allows me to start a container with an HTTP server on port `8080` that serves just the file `index.html`.

To create a corresponding image we need:
* A statically linked executable server - Which means that all dependencies are baked into the binary. Otherwise, the dependencies have to be provided by the environment - the image.
* The `index.html` file

### Statically Linked Server

We create a simple go server that serves all files
in the directory `/www` on port `8080`:
```go
// serve.go
package main

import (
    "net/http"
)

func main() {
    fs := http.FileServer(http.Dir("/www/"))
    http.Handle("/", fs)

    http.ListenAndServe("0.0.0.0:8080", nil)
}
```

I compile the server with:<br/>
`env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o serve`

Read [here](https://oddcode.daveamit.com/2018/08/16/statically-compile-golang-binary/) if you
want to know more about it.

### Index.html
As `index.html` I simply use:
```html
<html>
  <head><title>Hello from manual image</title></head>
  <body>
    Served from a manually created image. Awesome.
  </body>
</html
```

### Dockerfile
A Dockerfile is not necessary to create an image manually, but
first I want to understand what I want to create.

The following Dockerfile creates a corresponding image:
```Dockerfile
FROM scratch

COPY ./serve /server/
COPY ./index.html /www/

EXPOSE 8080

ENTRYPOINT ["/server/serve"]
```

The keyword `scratch` makes the `FROM` command a NoOp and the
resulting image will only consist of the layers defined by the 
subsequent commands.

Now I build the image and afterwards export it with
```bash
docker build . -t mini-image:1.0
docker save -o mini-image.tar mini-image:1.0
```

## Behind the Scenes

After extracting (example: `tar -zxvf mini-image.tar`) the tar file `mini-image.tar` I get:
```
mini-image.tar
├── 021..16d/
│   ├── VERSION
│   ├── json
│   └── layer.tar
├── 3ee..6b1/
│   ├── VERSION
│   ├── json
│   └── layer.tar
├── 3c3..22e.json
├── manifest.json
└── repositories
```

In order to understand this structure I take a look into the corresponding [specification v1.2](https://github.com/moby/moby/blob/master/image/spec/v1.2.md).

The key information of this specification are:
* The files `json` and `VERSION` are only necessary for backwards compatibility to the
  image specification [v1](https://github.com/moby/moby/blob/master/image/spec/v1.md).
* The file `repositories` "is only used for backwards compatibility. Current implementations use the manifest.json file instead".
* The "directory layout is only important for backward compatibility. Current implementations use the paths specified in `manifest.json`". Which means that the directory structure can be simplified.
* Each `layer.tar` file contains a "filesystem changeset for an image layer".
* The JSON file that has a hash name is also defined in the `manifest.json`.

A lot of complexity in this file structure comes from backwards compatiblity.
Since, I just want to understand what an image is, I don't care about this aspect.

## Target image

Therefore, I now aim for creating an image with the following structure:
```
manual-image.tar
├── layer_0.tar
├── layer_1.tar
├── config.json
└── manifest.json
```

## Create the image
I already know the content of the layers because I already defined
them in the previous Dockerfile.

Therefore, I start the image creation with preparing the layer tar files.

### Layers
I know that two layers necessary:
* Layer 0 - Add the binary `/server/serve`
* Layer 1 - Adds the file `/www/index.html`

One view into the [specification v1.2](https://github.com/moby/moby/blob/master/image/spec/v1.2.md#creating-an-image-filesystem-changeset)
 shows that in this case I simply have to store the files and the directories of each layer in a tar. Therefore,
 the layer creation is simple.

I create the tar files without compressions with `tar -cf <tarname>.tar -C <dir name>`.
Otherwise, the [DiffID calculation for the meta data files](#image-json-description) would be more complex.

This leads to the tar files:
```
layer_0.tar
└── server
    └── serve
layer_1.tar
└── www
    └── index.html
```
 
### Manifest

I already created the layers but I still do not know the purpose of the `manifest.json` and the `config.json`?

The manifest is the central configuration that:
* References the image JSON description (which I named `config.json`),
* defines the image/repo tags,
* and references the tar files that define the image's layers.

For my purpose the `manifest.json` can be:
```json
[
  {
      "Config": "config.json",
      "RepoTags": [
          "manual-mini-image:1.0"
      ],
      "Layers": [
          "layer_0.tar",
          "layer_1.tar"
      ]
  }
]
```

This config references the image description, defines that the image will be tagged with `manual-mini-image:1.0` when it is loaded, and defines **the location** and **the order** of the image layers.

### Image JSON Description

*Side note:* In the previous section I found out that I do not have to use a hash name for this file,
but what kind of hash is this? This hash is the sha256 hash of the Image JSON Descriptor file
content and is also the ImageID. Therefore, even if I don't need this hash for creating
the image it is interesting to understand the image concept.

This file contains a lot of image-related meta data (see the [specification v1.2](https://github.com/moby/moby/blob/master/image/spec/v1.2.md) for more details).
The interesting data for the minimal image are:
* The exposed ports (is not necessary) - `8080`
* The entrypoint - `./server/serve`
* The target system - `linux` and `amd64`
* The image's filesystem definition

Therefore, the only piece of data I still need is the filesystem definition which is defined by a list of
DiffIDs. A DiffID is a sha256 digest of the *uncompressed* layer tar. Therefore, I avoided to
compress the layers during the layer creation.

The digest can be determined with `sha256sum layer_(0|1).tar`.

This leads to the following image JSON description (`LAYER_(0|1)_DIFFID` are just placeholders):
```json
{
    "architecture": "amd64",
    "config": {
        "ExposedPorts": {
            "8080/tcp": {}
        },
        "Entrypoint": [
            "/server/serve"
        ]
    },
    "os": "linux",
    "rootfs": {
        "type": "layers",
        "diff_ids": [
            "sha256:LAYER_0_DIFFID",
            "sha256:LAYER_1_DIFFID"
        ]
    }
}
```

### Create tar

The last remaining step is to create the image tar.
At the end I have the following directory structure:

```
./
└── image/
    ├── layer_0.tar
    ├── layer_1.tar
    ├── config.json
    └── manifest.json
```

The command to create a corresponding tar image is
`tar -cf image.tar -C image .`.

I load the image into docker with `docker load --input image.tar`.
And `docker images` lists:
```
manual-mini-image   1.0                 85c2c5fe260f   N/A           6.48MB
```

I Start the container with
`docker run -d -p 8080:8080 manual-mini-image:1.0`

And test it with `curl http://localhost:8080`

### Plug everything together

This repository plugs all described aspects together and
provides a Makefile that automates:
* Building the image - `make build`
* Loading the image - `make load`
* Run the container - `make run`
* Test the container with curl - `make test`

During these processes two directories are created:
* `preparation` - This directory contains the layer directories before `tar` is executed.
* `image` - This directory contains all data as in the `image.tar`.
