# OPA Benchmarking Journey

Someone in a meeting questioned whether OPA could handle our performance requirements. Instead of arguing about it, I decided to find out.

## Why this exists

We were evaluating OPA for a high-throughput policy service. The usual questions came up in architecture reviews: "Is OPA fast enough?" "How does it scale?" "What happens with complex policies?"

People had strong opinions but nobody had actual numbers. The documentation says OPA is "high-performance" but doesn't define what that means. Blog posts show toy examples that don't reflect real complexity. I needed to know what we'd actually get in production.

So instead of guessing, I built a comprehensive test suite. This repo is what happened when I spent a weekend systematically measuring every OPA optimization technique I could find. (Full disclosure: Claude Code helped me write a lot of the automation - turns out AI is pretty good at generating benchmark scripts.)

Turns out OPA is pretty fast. But the details matter more than I expected.

## What this actually tests

Six different approaches to OPA deployment, using the same three policies with increasing complexity:

- **Simple RBAC** (28 lines): Basic role checks
- **API Authorization** (130 lines): JWT validation, rate limiting, time windows  
- **Financial Risk Assessment** (455 lines): Complex calculations, multiple data sources

The policies stay the same across all tests. Only the deployment method changes. This way you can actually see what each optimization does.

## How to recreate this

Fair warning: this isn't a simple tutorial. I tested everything from basic CLI evaluation to Kubernetes deployments with profile-guided optimizations. Some of it's straightforward, some of it gets pretty deep into the weeds.

### The basics (start here)

You need Docker and make. That's it.

```bash
# Build the baseline container
make build

# Run the simplest benchmark (CLI evaluation)
make opa-cli-benchmark ITERATIONS=1000

# Run server mode benchmark  
make opa-server-benchmark ITERATIONS=1000
```

This gives you the foundation: CLI vs server mode performance. Server mode should be 2-4x faster. If it's not, something's wrong with your setup.

### Testing concurrency

```bash
# Test how OPA handles multiple simultaneous requests
make opa-concurrent-benchmark ITERATIONS=200
```

I learned the hard way that Apache Bench gives you garbage data for this. The script uses actual curl processes in parallel because AB was measuring HTTP 400 errors instead of policy evaluation. Always validate what you're measuring.

### WebAssembly compilation

This is where things get interesting. WASM makes simple policies slower but complex policies much faster.

```bash
# Compiles policies to WASM and compares performance
make opa-wasm-benchmark ITERATIONS=500
```

Note: This builds OPA from source with CGO enabled. Takes a while but you get real WASM support, not just the runtime.

### Profile-guided optimization

```bash
# Collects performance profiles
make opa-profiling-benchmark ITERATIONS=100

# Tests optimized policy versions based on profiling data  
make opa-optimization-benchmark ITERATIONS=1000
```

I hand-optimized the policies based on profiling data. Early rejection patterns, cached calculations, lookup tables instead of conditional chains. The complex financial policy got 15% faster, simple policies stayed the same.

### Running on Kubernetes

This is where you see the biggest performance gains. Cloud infrastructure with proper horizontal scaling changes everything.

If you have a Kubernetes cluster (any cluster - minikube, kind, your own), you can run the cloud benchmarks:

```bash
# Deploy OPA with optimized policies to your cluster
kubectl apply -f k8s/opa-configmap-deployment.yaml

# Wait for pods to be ready
kubectl get pods -l app=opa-optimized

# Run 3-node benchmark (adjust parallelism based on your node count)
kubectl apply -f k8s/simple-benchmark-job.yaml

# Check results
kubectl logs -l app=opa-3node-benchmark

# Scale up and test again
kubectl scale deployment opa-optimized --replicas=15
kubectl apply -f k8s/5node-benchmark-job.yaml
kubectl logs -l app=opa-5node-benchmark
```

The Kubernetes setup uses ConfigMaps instead of custom images. I originally wanted to build a custom container with embedded policies, but Docker authentication got messy. ConfigMaps work better anyway - easier to iterate on policies.

## What you'll find in here

```
policies/               # Original Rego policies  
policies-optimized/     # Profile-guided optimized versions
data/                   # Test datasets
scripts/               # All the benchmark scripts
docker/                # Container definitions for each benchmark type
k8s/                   # Kubernetes manifests
```

The policies are real. Not toy examples. The financial risk assessment policy handles credit scoring, employment verification, collateral analysis - stuff you'd actually see in production.

## Things that will probably break

OPA versions matter. Make sure you use the same version everywhere. I tested with OPA 1.7.1.

WASM compilation is finicky. Requires glibc, not Alpine musl. CGO_ENABLED=1. Custom build process. Worth it for complex policies, too much hassle for simple ones.

Kubernetes resource allocation matters. Too little CPU and you get throttled. Too much and you waste money. 800m CPU, 1Gi RAM per OPA pod worked for me.

## The honest truth

Some optimizations barely matter. Bundle API flags? No measurable difference. Profile-guided optimization on simple policies? Actually made them slightly slower.

But the big wins are real. Server mode over CLI, horizontal scaling, proper concurrency handling - these make a huge difference. The complex financial policy went from 72 req/s (CLI) to 900 req/s (optimized Kubernetes deployment). That's not marketing BS, that's measurement.

## If you just want the takeaways

1. Never use CLI mode in production. Server mode is always faster.
2. Concurrency helps - 8 workers per instance is optimal, but scales linearly across multiple instances.  
3. WASM only helps complex policies. Skip it for simple RBAC.
4. Cloud infrastructure provides 4-5x performance improvement over local Docker.
5. Always validate that your benchmarks measure what you think they measure.

## Running this yourself

You don't need AWS or any specific cloud provider. Any Kubernetes cluster works. I tested on EKS but the manifests should work anywhere.

Start with the local Docker benchmarks to understand the baseline. Then move to Kubernetes if you want to see how it scales. The whole thing is designed to be reproducible.

Just don't expect it to be quick. Comprehensive benchmarking takes time. But you'll actually know what OPA performance looks like in your environment instead of guessing based on blog posts.

Let's see if this helps anyone else avoid the "is OPA fast enough?" uncertainty.