# OPA Benchmarking Journey

A systematic, reproducible test suite for measuring OPA performance across deployment modes—from CLI to Kubernetes.

📖 **Read the full analysis:** [The OPA Performance Investigation](https://mannustack.com/posts/opa-performance-investigation/) - Complete findings, methodology, and production recommendations.

## TL;DR Results

- **Server mode:** 2.4×–3.7× faster than CLI
- **WASM:** +14% for complex policies, -4% for simple ones  
- **Kubernetes:** 10–11× faster than CLI (816 vs 74.62 req/s for complex policies)
- **Concurrency:** 1.13×–1.56× scaling (4–8 workers optimal)

This repo contains the benchmarking tools to reproduce these measurements in your own environment.

## Test Policies

Three policies with increasing complexity (same across all benchmarks):

- **Simple RBAC** (38 lines, 6 rules): Basic role-based access control
- **API Authorization** (140 lines, 13 rules): JWT validation, rate limiting, time windows  
- **Financial Risk Assessment** (457 lines, 67 rules): Complex calculations, credit scoring, employment verification

Same policies, same data—only deployment knobs change. This isolates the impact of each optimization.

## Quick Start (5 Minutes)

**Prerequisites:** Docker + `make` + `kubectl` (for Kubernetes tests)

### Local Benchmarks

```bash
# Build containers
make build

# CLI vs Server (foundation test)
make opa-cli-benchmark ITERATIONS=100
make opa-server-benchmark ITERATIONS=100
```

Expected result: Server mode ~2.4×–3.7× faster than CLI.

### Advanced Benchmarks

```bash
# Concurrency scaling
make opa-concurrent-benchmark ITERATIONS=100

# WebAssembly compilation (builds OPA from source)
make opa-wasm-benchmark ITERATIONS=100

# Profile-guided optimization
make opa-profiling-benchmark ITERATIONS=100
make opa-optimization-benchmark ITERATIONS=100
```

**Key findings:**
- **Concurrency:** 1.13×–1.56× scaling (4–8 workers optimal)
- **WASM:** Helps complex policies (+14%), hurts simple ones (-4%)
- **Profiling:** +11% for complex policies, negligible for simple ones

### Kubernetes Benchmarks

```bash
# Deploy OPA with optimized policies (any cluster: minikube/kind/GKE/AKS/EKS)
kubectl apply -f k8s/opa-configmap-deployment.yaml

# Wait for pods
kubectl get pods -l app=opa-optimized

# 3-node benchmark
kubectl apply -f k8s/simple-benchmark-job.yaml
kubectl logs -l app=opa-3node-benchmark

# Scale and retest
kubectl scale deployment opa-optimized --replicas=15
kubectl apply -f k8s/5node-benchmark-job.yaml
kubectl logs -l app=opa-5node-benchmark
```

Expected: **10–11× improvement** over CLI, near-linear horizontal scaling.

## Repository Structure

```
policies/               # Original Rego policies  
policies-optimized/     # Profile-guided optimized versions
data/                   # Test datasets
scripts/               # Benchmark automation scripts
docker/                # Container definitions for each benchmark type
k8s/                   # Kubernetes manifests
```

## Production Notes

- **OPA Version:** All tests use v1.7.1 for consistency
- **WASM Requirements:** CGO_ENABLED=1, glibc (not Alpine musl)
- **K8s Resources:** 800m CPU, 1Gi RAM per pod worked well
- **Cloud Provider:** Any cluster works (minikube/kind/GKE/AKS/EKS)

## Expected Results

**Sanity check for Financial Risk Assessment (complex policy):**
- CLI: ~75 req/s, P95 ~18ms
- Server: ~278 req/s, P95 ~5ms (≈3.7× improvement)
- 4-node K8s: ~816 req/s, P95 ~5ms (≈10.9× improvement)

## Quick Results Extraction

```bash
# Scan for key metrics
grep -E "P95|Requests/Sec" ./results/*.txt

# Look for timing in console output
```

📖 **For complete analysis, methodology, and production recommendations:** [The OPA Performance Investigation](https://mannustack.com/posts/opa-performance-investigation/)