# eks-brokerpak

## Why this project

The EKS brokerpak is a
[cloud-service-broker](https://github.com/pivotal/cloud-service-broker) plugin
that makes AWS EKS brokerable via the [Open Service Broker API](https://www.openservicebrokerapi.org/) (compatible with Cloud Foundry and Kubernetes), using Terraform.

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

Run the `make` command by itself for information on the various targets that are available. Notable targets are described below

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

## Building and starting the brokerpak 
Run 

```
make build up wait
```
The broker will start and (after about 40 seconds) listen on `0.0.0.0:8080`. You
test that it's responding by running:
```
curl -i -H "X-Broker-API-Version: 2.16" http://user:pass@127.0.0.1:8080/v2/catalog
```
In response you will see a YAML description of the services and plans available
from the brokerpak.

(Note that the `X-Broker-API-version` header is [**required** by the OSBAPI
specification](https://github.com/openservicebrokerapi/servicebroker/blob/master/spec.md#headers).
The broker will reject requests that don't include the header with `412
Precondition Failed`, and browsers will show that status as `Not Authorized`.)

You can also inspect auto-generated documentation for the brokerpak's offerings
by visiting [`http://127.0.0.1:8080/docs`](http://127.0.0.1:8080/docs) in your browser.

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

