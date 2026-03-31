# Cloud Native Architecture (12%)

This domain covers the principles and patterns behind cloud native application design, including microservices, the 12-factor app methodology, serverless computing, and the CNCF ecosystem. While it carries the smallest weight (12%), the concepts here provide the foundation for understanding why tools like Kubernetes exist and how they fit into the broader cloud native landscape.

!!! tip "Exam Tip"
    Pay special attention to the CNCF's official definition of cloud native and the organizational structures (SIGs, Working Groups, KEPs). These are frequently tested topics that are easy points.

## What is Cloud Native?

### CNCF Definition

The [Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/) defines cloud native technologies as those that:

> "...empower organizations to build and run scalable applications in modern, dynamic environments such as public, private, and hybrid clouds. Containers, service meshes, microservices, immutable infrastructure, and declarative APIs exemplify this approach."

Key characteristics of cloud native applications:

- **Containerized** -- Each part of the application is packaged in its own container.
- **Dynamically orchestrated** -- Containers are actively scheduled and managed to optimize resource utilization.
- **Microservices-oriented** -- Applications are broken into loosely coupled, independently deployable services.
- **Automated** -- CI/CD pipelines, infrastructure as code, and automated testing.
- **Resilient** -- Designed to handle failures gracefully.
- **Observable** -- Built-in logging, monitoring, and tracing.

### Cloud Native Trail Map

The CNCF Trail Map provides a recommended path for adopting cloud native technologies:

1. **Containerization** -- Package applications in containers.
2. **CI/CD** -- Automate build, test, and deployment.
3. **Orchestration** -- Use Kubernetes to manage containers.
4. **Observability & Analysis** -- Implement monitoring, logging, and tracing.
5. **Service Mesh** -- Manage service-to-service communication.
6. **Networking & Security** -- Apply policies and encryption.
7. **Distributed Database & Storage** -- Use cloud native storage solutions.
8. **Messaging & Streaming** -- Implement event-driven architectures.
9. **Container Registry & Runtime** -- Manage images and runtimes.
10. **Software Distribution** -- Distribute and manage software artifacts.

## Microservices Architecture

Microservices is an architectural style where an application is structured as a collection of small, autonomous services that communicate over well-defined APIs.

### Microservices vs Monoliths

| Aspect | Monolith | Microservices |
|---|---|---|
| Deployment | Single unit | Independent per service |
| Scaling | Scale entire application | Scale individual services |
| Technology | Single tech stack | Polyglot (mix of languages) |
| Team structure | One large team | Small, autonomous teams |
| Failure impact | Entire app affected | Isolated to single service |
| Complexity | Simpler initially | More complex infrastructure |
| Data management | Shared database | Database per service |

### Benefits of Microservices

- Independent deployment and scaling of services.
- Technology flexibility -- each service can use the best tool for the job.
- Fault isolation -- a failure in one service does not bring down the entire application.
- Team autonomy -- small teams can own and operate individual services.

### Challenges of Microservices

- Increased operational complexity (networking, monitoring, debugging).
- Distributed system challenges (network latency, eventual consistency, distributed tracing).
- Requires mature DevOps practices and tooling.

## The 12-Factor App

The [12-Factor App](https://12factor.net/) methodology defines best practices for building modern, cloud native applications. These principles are highly relevant to Kubernetes deployments:

| Factor | Description | Kubernetes Relevance |
|---|---|---|
| **I. Codebase** | One codebase tracked in version control | Git-based workflows, GitOps |
| **II. Dependencies** | Explicitly declare and isolate dependencies | Container images, `requirements.txt` |
| **III. Config** | Store config in the environment | ConfigMaps, Secrets, env vars |
| **IV. Backing Services** | Treat backing services as attached resources | Services, ExternalName, connection strings |
| **V. Build, Release, Run** | Strictly separate build and run stages | CI/CD pipelines, container image tags |
| **VI. Processes** | Execute the app as stateless processes | Pods are ephemeral, use external storage |
| **VII. Port Binding** | Export services via port binding | Container ports, Services |
| **VIII. Concurrency** | Scale out via the process model | Horizontal Pod Autoscaler, ReplicaSets |
| **IX. Disposability** | Maximize robustness with fast startup and graceful shutdown | Pod lifecycle, preStop hooks, SIGTERM |
| **X. Dev/Prod Parity** | Keep development, staging, and production similar | Namespaces, Helm, Kustomize overlays |
| **XI. Logs** | Treat logs as event streams | stdout/stderr, log aggregation |
| **XII. Admin Processes** | Run admin/management tasks as one-off processes | Jobs, CronJobs |

!!! tip "Exam Tip"
    You do not need to memorize all 12 factors by number, but you should be able to recognize them and explain how Kubernetes supports each principle. Factor III (Config), Factor VI (Processes), and Factor VIII (Concurrency) are particularly relevant.

## Serverless

Serverless computing abstracts infrastructure management so developers can focus solely on code. The cloud provider handles provisioning, scaling, and maintenance.

### Key Characteristics

- **No server management** -- Infrastructure is fully managed by the platform.
- **Event-driven** -- Functions are triggered by events (HTTP requests, messages, timers).
- **Automatic scaling** -- Scales from zero to peak demand automatically.
- **Pay-per-use** -- Billed only for actual execution time and resources consumed.

### Serverless in the Kubernetes Ecosystem

- **Knative** -- A CNCF incubating project that extends Kubernetes with serverless capabilities (serving and eventing).
- **OpenFaaS** -- Functions as a Service framework for Kubernetes.
- **KEDA** (Kubernetes Event-Driven Autoscaling) -- A CNCF graduated project that scales workloads based on event sources.

## Autoscaling Patterns

Kubernetes supports multiple levels of autoscaling:

- **Horizontal Pod Autoscaler (HPA)** -- Adjusts the number of Pod replicas based on observed CPU utilization, memory usage, or custom metrics.
- **Vertical Pod Autoscaler (VPA)** -- Adjusts resource requests and limits for containers based on historical usage.
- **Cluster Autoscaler** -- Adjusts the number of nodes in the cluster when Pods cannot be scheduled due to insufficient resources or when nodes are underutilized.
- **KEDA** -- Scales workloads to and from zero based on external event sources (message queues, databases, custom metrics).

## Community and Governance

### CNCF (Cloud Native Computing Foundation)

The CNCF is part of the Linux Foundation and hosts critical cloud native infrastructure projects. It organizes projects into maturity levels:

- **Graduated** -- Mature, production-ready projects (e.g., Kubernetes, Prometheus, Envoy, containerd, Helm, Argo, Flux).
- **Incubating** -- Growing projects with increasing adoption (e.g., Knative, CRI-O, Backstage).
- **Sandbox** -- Early-stage projects with potential.

### Kubernetes Community Structure

- **SIGs (Special Interest Groups)** -- Permanent groups that own specific areas of the Kubernetes project (e.g., SIG-Network, SIG-Storage, SIG-Auth). Each SIG has defined responsibilities and regular meetings.
- **Working Groups** -- Temporary, cross-SIG groups formed to address specific topics that span multiple SIGs.
- **KEPs (Kubernetes Enhancement Proposals)** -- The formal process for proposing, designing, and implementing significant changes to Kubernetes. Similar to RFCs in other projects.
- **KubeCon + CloudNativeCon** -- The flagship CNCF conference held multiple times per year in different regions.

## Important Links

- [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md)
- [CNCF Landscape](https://landscape.cncf.io/)
- [The 12-Factor App](https://12factor.net/)
- [CNCF Project Maturity Levels](https://www.cncf.io/projects/)
- [Kubernetes SIGs](https://github.com/kubernetes/community/blob/master/sig-list.md)
- [KEP Process](https://www.kubernetes.dev/resources/keps/)
- [Knative](https://knative.dev/)

## Practice Questions

??? question "What are the three maturity levels for CNCF projects?"
    Think about how the CNCF categorizes its hosted projects based on maturity.

    ??? success "Answer"
        The three CNCF maturity levels are **Sandbox**, **Incubating**, and **Graduated**. Sandbox projects are early-stage and experimental. Incubating projects have growing adoption and community. Graduated projects are considered stable, production-ready, and widely adopted (e.g., Kubernetes, Prometheus, Envoy, containerd). Projects must meet specific criteria to advance between levels, including adoption metrics, security audits, and governance requirements.

??? question "Which 12-Factor App principle does Kubernetes support through ConfigMaps and Secrets?"
    Consider how Kubernetes separates application code from environment-specific settings.

    ??? success "Answer"
        **Factor III: Config** -- "Store config in the environment." Kubernetes ConfigMaps and Secrets allow you to externalize configuration from container images and inject it into Pods as environment variables or mounted files. This means the same container image can be used across development, staging, and production environments with different configurations, following the strict separation of config from code.

??? question "What is the role of a SIG in the Kubernetes community?"
    Consider how the Kubernetes project is organized and maintained.

    ??? success "Answer"
        A **SIG (Special Interest Group)** is a permanent community group that owns a specific area of the Kubernetes project. Each SIG is responsible for the design, development, testing, and maintenance of their area (e.g., SIG-Network owns networking, SIG-Storage owns storage). SIGs hold regular meetings, maintain documentation, and review proposals (KEPs) related to their domain. They are the primary organizational unit for Kubernetes development.

??? question "How does serverless differ from traditional container orchestration?"
    Think about who manages the infrastructure and how scaling works.

    ??? success "Answer"
        In traditional container orchestration (e.g., running workloads on Kubernetes), you manage the cluster, define resource requests, and configure autoscaling policies. In **serverless**, the platform fully abstracts infrastructure management -- there are no servers or clusters to manage. Functions scale automatically (including to zero when idle), are triggered by events, and you pay only for actual execution time. In the Kubernetes ecosystem, projects like **Knative** and **KEDA** bring serverless patterns to Kubernetes clusters.

??? question "A company is migrating a monolithic application to microservices on Kubernetes. Which challenge should they anticipate?"
    Consider the trade-offs between monolithic and microservices architectures.

    ??? success "Answer"
        The company should anticipate **increased operational complexity**. Microservices introduce distributed system challenges including network latency between services, the need for service discovery and load balancing, distributed tracing for debugging, eventual consistency in data management, and more complex deployment pipelines. They will need mature DevOps practices, proper observability (logging, monitoring, tracing), and potentially a service mesh to manage service-to-service communication. While Kubernetes helps manage this complexity, it does not eliminate it.
