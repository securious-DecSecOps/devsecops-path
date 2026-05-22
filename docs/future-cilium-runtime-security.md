# Future Cilium Runtime Security

Cilium is not implemented in v1.

It belongs in the runtime security and network policy layer:

```text
Kubernetes Deploy
-> Cilium NetworkPolicy
-> eBPF visibility
-> runtime evidence
```

Future runtime security expansion may include:

- Cilium
- Falco
- NetworkPolicy
- runtime observability
- Kubescape

Expected future evidence:

- policy manifests
- policy enforcement state
- flow visibility output
- runtime alert summaries

