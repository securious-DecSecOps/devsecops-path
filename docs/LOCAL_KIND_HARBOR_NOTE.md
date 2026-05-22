# Local kind + Harbor Registry Note

## Why the local Harbor setup was confusing

In the template local environment, the registry endpoint is:

```text
localhost:9092
```

This works from the WSL/Docker host when a registry or Harbor-compatible
endpoint is actually listening on host port `9092`.

The older local lab may already expose Harbor on `localhost` port `8082`; this
template uses `9092` to avoid that conflict.

However, kind Kubernetes nodes are themselves Docker containers.

So inside a kind worker node:

```text
localhost:9092
```

does not mean the WSL host's Harbor.

It means:

```text
the kind worker node container itself
```

If the mirror is missing, image pull can fail with an error like:

```text
dial tcp [::1]:9092: connect: connection refused
```

## Why containerd mirror was needed

The actual image pull actor is:

```text
kind worker node containerd
```

To make `localhost:9092` work inside kind, containerd needed a registry mirror rule:

```toml
server = "http://localhost:9092"

[host."http://172.18.0.1:9092"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
```

Meaning:

```text
When containerd sees localhost:9092,
actually reach Docker host gateway 172.18.0.1:9092.
```

## Is this production-like?

No.

This is a local-kind workaround.

In production/AWS, use a real registry address:

```text
harbor.example.internal
123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
```

Do not rely on localhost or skip_verify in production.
