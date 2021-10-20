FROM hashicorp/terraform:0.12.31 as terraform

FROM alpine/k8s:1.20.7

COPY --from=terraform /bin/terraform /bin/terraform 

RUN apk update
RUN apk add --update git bind-tools

ENTRYPOINT ["/bin/sh"]
