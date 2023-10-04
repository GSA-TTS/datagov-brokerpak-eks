FROM hashicorp/terraform:1.1.5 as terraform

FROM alpine/k8s:1.23.17

COPY --from=terraform /bin/terraform /bin/terraform 

RUN apk update
RUN apk add --update git 

ENTRYPOINT ["/bin/sh"]
