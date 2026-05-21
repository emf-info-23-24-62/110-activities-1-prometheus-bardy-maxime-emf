# PromQL - Prometheus Query Language

PromQL (Prometheus Query Language) est le langage de requête de Prometheus. Ce guide vous accompagne des bases aux requêtes avancées, avec des exemples concrets que vous pouvez tester immédiatement.


## Premiers pas avec PromQL
Accédez à l’interface Prometheus (http://localhost:9090) et utilisez l’onglet Graph pour tester vos requêtes.

### Requête la plus simple

Tapez le nom d’une métrique pour voir toutes ses séries :
```bash
up
```
Résultat : toutes les séries de la métrique up, une par target scrapée.
```bash
up{instance="localhost:9090", job="prometheus"} 1
up{instance="node1:9100", job="node"} 1
up{instance="node2:9100", job="node"} 0
```

### Filtrer avec les labels

Les sélecteurs de labels filtrent les séries :
```bash
up{job="node"}
```
### Opérateurs de matching

| Opérateur | Description        | Exemple             |
|-----------|--------------------|---------------------|
| =         | Égalité exacte     | job="prometheus"    |
| !=        | Différent de       | job!="test"         |
| =~        | Regex match        | job=~"node.*"       |
| !~        | Regex not match    | job!~"test.*"       |


## Types de données

PromQL manipule quatre types de données :

| Type           | Description                                  | Exemple            |
|----------------|----------------------------------------------|--------------------|
| Instant vector | Valeurs actuelles (un point par série)       | up                 |
| Range vector   | Valeurs sur une période                      | up[5m]             |
| Scalar         | Nombre flottant                              | 3.14               |
| String         | Chaîne (rarement utilisé)                    | "hello"            |

### Instant vector

C’est le type le plus courant. Chaque série a une seule valeur (la dernière).
```bash
node_memory_MemAvailable_bytes
```
### Range vector

Sélectionne toutes les valeurs sur une période. Nécessaire pour les fonctions comme `rate()`.
```bash
http_requests_total[5m]
```
Périodes disponibles :  
`s` (secondes), `m` (minutes), `h` (heures), `d` (jours), `w` (semaines), `y` (années)

⚠️ Range vector seul = pas affichable  

Un range vector ne peut pas s’afficher directement. Vous devez appliquer une fonction (`rate`, `increase`, `avg_over_time`…) qui retourne un instant vector.

## Opérateurs

### Opérateurs arithmétiques

Les opérateurs classiques fonctionnent sur les séries :
```bash
# Mémoire utilisée en pourcentage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
```

| Opérateur | Description     |
|----------|-----------------|
| +        | Addition        |
| -        | Soustraction    |
| *        | Multiplication  |
| /        | Division        |
| %        | Modulo          |
| ^        | Puissance       |

### Opérateurs de comparaison

Retournent `1` (vrai) ou filtrent les séries :
```bash
# Instances avec CPU > 80%
instance:cpu_usage:percent > 80
```
```bash
# Garder uniquement les séries au-dessus du seuil
http_request_duration_seconds > 0.5
```
| Opérateur | Description           |
|----------|-----------------------|
| ==       | Égal                  |
| !=       | Différent             |
| >        | Supérieur             |
| <        | Inférieur             |
| >=       | Supérieur ou égal     |
| <=       | Inférieur ou égal     |

### Opérateurs logiques

Pour combiner des vecteurs :
```bash
# Séries présentes dans les deux (intersection)
metric_a and metric_b

# Séries présentes dans l'un ou l'autre (union)
metric_a or metric_b

# Séries de A absentes de B
metric_a unless metric_b
```

## Fonctions essentielles

### rate() — Taux de variation

La fonction la plus importante. Calcule le taux par seconde d’un counter.
```bash
# Requêtes par seconde (sur 5 minutes)
rate(http_requests_total[5m])
```
⚠️ `rate()` uniquement sur les counters  
`rate()` est conçu pour les métriques de type counter (valeurs croissantes). Pour les gauges, utilisez d’autres fonctions.

### irate() — Taux instantané

Comme `rate()` mais utilise uniquement les 2 derniers points. Plus réactif mais plus bruité.
```bash
# Taux instantané (derniers 5 min de données)
irate(http_requests_total[5m])
```

### increase() — Augmentation totale

Nombre total d’augmentations sur la période.
```bash
# Nombre de requêtes sur 1 heure
increase(http_requests_total[1h])
```
### sum(), avg(), min(), max() — Agrégations

Agrègent plusieurs séries en une.
```bash
# Total des requêtes (toutes instances)
sum(rate(http_requests_total[5m]))

# Moyenne de mémoire par node
avg(node_memory_MemAvailable_bytes)

# Maximum de CPU
max(instance:cpu_usage:percent)
```
### Agrégation par label

Utilisez `by` ou `without` pour contrôler l’agrégation :
```bash
# Somme par job
sum by(job) (rate(http_requests_total[5m]))

# Somme en ignorant le label instance
sum without(instance) (rate(http_requests_total[5m]))
```

### histogram_quantile() — Percentiles

Calcule les percentiles depuis un histogram.
```bash
# P95 de latence par job
histogram_quantile(0.95,
  sum by(job, le) (rate(http_request_duration_seconds_bucket[5m]))
)

# P99 global
histogram_quantile(0.99,
  sum by(le) (rate(http_request_duration_seconds_bucket[5m]))
)
```

`le` (less than or equal) est le label spécial des histograms qui contient les bornes des buckets.  
Il doit toujours être préservé dans l’agrégation.


### Fonctions mathématiques

| Fonction | Description           | Exemple                     |
|----------|-----------------------|-----------------------------|
| abs()    | Valeur absolue        | abs(delta(temp[1h]))        |
| ceil()   | Arrondi supérieur     | ceil(value)                 |
| floor()  | Arrondi inférieur     | floor(value)                |
| round()  | Arrondi               | round(value, 0.1)           |
| ln()     | Logarithme naturel    | ln(value)                   |
| log2()   | Log base 2            | log2(value)                 |
| log10()  | Log base 10           | log10(value)                |
| sqrt()   | Racine carrée         | sqrt(value)                 |


### Fonctions temporelles

| Fonction        | Description                       |
|-----------------|-----------------------------------|
| time()          | Timestamp Unix actuel             |
| timestamp()     | Timestamp de chaque sample        |
| day_of_week()   | Jour de la semaine (0-6)          |
| hour()          | Heure (0-23)                      |

```bash
# Alerte uniquement en heures ouvrées
up == 0 and hour() >= 9 and hour() <= 18
```

---

# Réaliser des reqûetes PromQL

Dans cette partie, vous allez écrire des requêtes PromQL à partir des métriques exposées par :

- l'application **NodeJS**
- le serveur **Ubuntu** via **Node Exporter**

## Requêtes progressives sur l'application NodeJS

### Question 1 — Requête simple
Affiche uniquement le total des requêtes HTTP de la route `/health`.

**Réponse :**

    http_requests_total{route="/health"}


### Question 2 — Requête simple
Affiche uniquement les requêtes HTTP en erreur `404`.

**Réponse :**

    http_requests_total{status_code="404"}


### Question 3 — Requête avec opérateurs arithmétiques
En NodeJS, le **heap** est une zone mémoire utilisée pour stocker les données dynamiques.

Calcule le **pourcentage de heap NodeJS utilisée**.

**Réponse :**

    (nodejs_heap_size_used_bytes / nodejs_heap_size_total_bytes) * 100


### Question 4 — Requête avec opérateurs arithmétiques
Calcule la **durée moyenne des requêtes réussies** sur la route `/slow`.

Astuce : utilise `_sum` et `_count`.

**Réponse :**

    http_request_duration_seconds_sum{route="/slow",status_code="200"}
      /
    http_request_duration_seconds_count{route="/slow",status_code="200"}


### Question 5 — Requête avec opérateurs de comparaison
Affiche les séries où le **nombre total de requêtes HTTP est supérieur à 10**.

**Réponse :**

    http_requests_total > 10


### Question 6 — Requête avec opérateurs logiques
Affiche les requêtes HTTP qui sont :

- sur `/health`
- ou en `404`

**Réponse :**

    http_requests_total{route="/health"} or http_requests_total{status_code="404"}


### Question 7 — Requête avec fonctions
Calcule le **taux de requêtes HTTP par seconde** sur 5 minutes pour `/metrics`.

**Réponse :**

    rate(http_requests_total{route="/metrics"}[5m])


### Question 8 — Requête avec fonctions
Calcule le **nombre total de requêtes HTTP GET**.

**Réponse :**

    sum(http_requests_total{method="GET"})


### Question 9 — Requête avec fonctions
En NodeJS, L’event loop c'est la boucle qui exécute en continu les tâches de ton programme. On peut voir si il y a du lag (le temps de retard entre quand une tâche devrait être exécutée) avec les metrics nodejs_eventloop_lag.

Affiche la **plus petite valeur de lag de l’event loop**.

**Réponse :**

    min_over_time(nodejs_eventloop_lag_seconds[5m])


### Question 10 — Requête avec fonctions
Affiche la **plus grande valeur de lag de l’event loop**.

**Réponse :**

    max_over_time(nodejs_eventloop_lag_seconds[5m])


## Requêtes avancées sur le serveur Ubuntu (Node Exporter)

### Question 1 — CPU
Calcule le **pourcentage d’utilisation CPU global** sur 5 minutes.

**Réponse :**

    100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)


### Question 2 — Mémoire
Calcule le **pourcentage de RAM utilisée**.

**Réponse :**

    (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100


### Question 3 — Disque
Affiche le **pourcentage d’occupation disque** de `/`.

**Réponse :**

    (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100


