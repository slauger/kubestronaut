# Resources

Curated collection of study resources for all five Kubestronaut certifications.

## Official Resources

| Resource | Description |
|---|---|
| [CNCF Curriculum](https://github.com/cncf/curriculum) | Official open-source curricula (PDF) for all certifications |
| [Kubernetes Docs](https://kubernetes.io/docs/) | Official documentation (allowed during exams) |
| [killer.sh](https://killer.sh/) | Official exam simulator (included with CKA/CKAD/CKS purchase) |
| [Killercoda](https://killercoda.com/) | Free interactive Kubernetes scenarios in the browser |
| [CNCF Training](https://www.cncf.io/training/) | Official training and certification portal |

## GitHub Repositories

### Multi-Certification / Kubestronaut

| Repository | Description |
|---|---|
| [cncf/curriculum](https://github.com/cncf/curriculum) | Official CNCF curricula for all certs |
| [yetmike/awesome-kubestronaut](https://github.com/yetmike/awesome-kubestronaut) | Curated resource list for all 5 certs |
| [schnatterer/ckad-cka-cks-kubestronaut](https://github.com/schnatterer/ckad-cka-cks-kubestronaut) | Tips for preparing all 5 certs |

### KCNA

| Repository | Description |
|---|---|
| [walidshaari/Kubernetes-and-Cloud-Native-Associate](https://github.com/walidshaari/Kubernetes-and-Cloud-Native-Associate) | Curated KCNA resources |
| [edithturn/KCNA-training](https://github.com/edithturn/KCNA-training) | KCNA study notes |

### KCSA

| Repository | Description |
|---|---|
| [thiago4go/kubernetes-security-kcsa-mock](https://github.com/thiago4go/kubernetes-security-kcsa-mock) | Interactive mock exam with 290+ questions |
| [yongkanghe/kcsa](https://github.com/yongkanghe/kcsa) | 150 KCSA mock questions |
| [iamaliyousefi/kcsa](https://github.com/iamaliyousefi/kcsa) | KCSA study sources |

### CKA

| Repository | Description |
|---|---|
| [walidshaari/Kubernetes-Certified-Administrator](https://github.com/walidshaari/Kubernetes-Certified-Administrator) | Curated CKA resources |
| [alijahnas/CKA-practice-exercises](https://github.com/alijahnas/CKA-practice-exercises) | Practice exercises with solutions |
| [chadmcrowell/CKA-Exercises](https://github.com/chadmcrowell/CKA-Exercises) | Hands-on CKA exercises |
| [bmuschko/cka-crash-course](https://github.com/bmuschko/cka-crash-course) | CKA crash course |
| [techiescamp/cka-certification-guide](https://github.com/techiescamp/cka-certification-guide) | Comprehensive CKA learning path |

### CKAD

| Repository | Description |
|---|---|
| [dgkanatsios/CKAD-exercises](https://github.com/dgkanatsios/CKAD-exercises) | Most popular CKAD exercise set |
| [bmuschko/ckad-crash-course](https://github.com/bmuschko/ckad-crash-course) | CKAD crash course |

### CKS

| Repository | Description |
|---|---|
| [techiescamp/cks-certification-guide](https://github.com/techiescamp/cks-certification-guide) | CKS learning path with study materials |
| [Killercoda CKS Labs](https://killercoda.com/killer-shell-cks) | Free interactive CKS browser labs |

## Online Courses

| Course | Platform | Certifications |
|---|---|---|
| Kubernetes for the Absolute Beginners | KodeKloud / Udemy | KCNA |
| CKA with Practice Tests (Mumshad Mannambeth) | Udemy | CKA |
| CKAD with Tests (Mumshad Mannambeth) | Udemy | CKAD |
| CKS (KodeKloud) | KodeKloud | CKS |
| Kubernetes Security (KCSA) | KodeKloud | KCSA |

## Study Guides (Blogs)

| Guide | Certification |
|---|---|
| [DevOpsCube KCNA Study Guide](https://devopscube.com/kcna-study-guide/) | KCNA |
| [DevOpsCube KCSA Study Guide](https://devopscube.com/kcsa-exam-study-guide/) | KCSA |
| [DevOpsCube CKA Study Guide](https://devopscube.com/cka-exam-study-guide/) | CKA |
| [DevOpsCube CKS Study Guide](https://devopscube.com/cks-exam-guide-tips/) | CKS |
| [Paul Yu's KCSA Study Guide](https://paulyu.dev/article/kcsa-study-guide/) | KCSA |

## Practice Exam Simulators

| Resource | Type | Certifications |
|---|---|---|
| [killer.sh](https://killer.sh/) | Official simulator (included with purchase) | CKA, CKAD, CKS |
| [KCSA Mock Exam](https://kubernetes-security-kcsa-mock.vercel.app/) | Free browser-based mock | KCSA |
| [Killercoda Scenarios](https://killercoda.com/) | Free interactive labs | CKA, CKAD, CKS |

## General Exam Tips

!!! tip "Performance-based Exams (CKA, CKAD, CKS)"
    - Master `kubectl` imperative commands — they save significant time
    - Use `kubectl explain <resource>` to look up field specs during the exam
    - Set up shell aliases early: `alias k=kubectl`, `export do="--dry-run=client -o yaml"`
    - Practice with `killer.sh` — it's harder than the actual exam
    - Bookmark key Kubernetes docs pages before the exam
    - Manage your time — skip hard questions and return later

!!! tip "Multiple Choice Exams (KCNA, KCSA)"
    - Read all answer options before selecting
    - Eliminate obviously wrong answers first
    - Focus on understanding concepts, not memorizing commands
    - Review the CNCF landscape and ecosystem projects
