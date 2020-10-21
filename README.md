# template-brokerpak

## Why this project

_This is a template repository that can be cloned by anyone who wants to develop a brokerpak for their own services. Fork or copy this repository, and edit references to XXXX to refer to your own team or service provider._

The XXXX brokerpak is a [cloud-service-broker](https://github.com/pivotal/cloud-service-broker) plugin that makes services
provided by XXXX brokerable via the [Open Service Broker API](https://www.openservicebrokerapi.org/) (compatible with Cloud Foundry and Kubernetes), using Terraform.

For more information about the brokerpak concept, here's a [5-minute lightning
talk](https://www.youtube.com/watch?v=BXIvzEfHil0) from the 2019 Cloud Foundry Summit. You may also want to check out the brokerpak
[introduction](https://github.com/pivotal/cloud-service-broker/blob/master/docs/brokerpak-intro.md)
and
[specification](https://github.com/pivotal/cloud-service-broker/blob/master/docs/brokerpak-specification.md)
docs.

Huge props go to @josephlewis42 of Google for publishing and publicizing the
brokerpak concept, and to the Pivotal team running with the concept!

## Prerequisites

1. [Docker Desktop (for Mac or
Windows)](https://www.docker.com/products/docker-desktop) or [Docker Engine (for
Linux)](https://www.docker.com/products/container-runtime) is used for
building, serving, and testing the brokerpak.
1. `make` is used for executing docker commands in a meaningful build cycle. 

Run the `make` command by itself for information on the various targets that are available. 

```
$ make
clean      Bring down the broker service if it's up, clean out the database, and remove created images
build      Build the brokerpak(s) and create a docker image for testing it/them
up         Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser.
test       Execute the brokerpak examples against the running broker
down       Bring the cloud-service-broker service down
all        Clean and rebuild, then bring up the server, run the examples, and bring the system down
help       This help
```
Notable targets are described below

## Building and starting the brokerpak 
Run 

```
make up
```

The broker will start and listen on `0.0.0.0:8080`. You can curl
http://127.0.0.1 or visit it in your browser.

## Testing the brokerpak (while it's running)

Run 
```
make test
```

The [examples specified by the
brokerpak](https://github.com/pivotal/cloud-service-broker/blob/master/docs/brokerpak-specification.md#service-yaml-flie)
will be invoked for end-to-end testing of the brokerpak's service offerings.

## Tearing down the brokerpak

Run 

```
make down
```

The broker will be stopped.

## Cleaning out the current state

Run 
```
make clean
```
The broker image, database content, and any built brokerpak files will be removed.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for additional information.

## Public domain

This project is in the worldwide [public domain](LICENSE.md). As stated in [CONTRIBUTING](CONTRIBUTING.md):

> This project is in the public domain within the United States, and copyright and related rights in the work worldwide are waived through the [CC0 1.0 Universal public domain dedication](https://creativecommons.org/publicdomain/zero/1.0/).
>
> All contributions to this project will be released under the CC0 dedication. By submitting a pull request, you are agreeing to comply with this waiver of copyright interest.

