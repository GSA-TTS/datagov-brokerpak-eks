FROM hashicorp/terraform:0.13.7 as terraform

FROM alpine/k8s:1.20.7

COPY --from=terraform /bin/terraform /bin/terraform 

RUN apk update
RUN apk add --update git 

ENTRYPOINT ["/bin/sh"]
