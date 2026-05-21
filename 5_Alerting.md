# Alertmanager : Routage et notification des alertes

Prometheus détecte un problème, mais comment êtes-vous prévenu ? Alertmanager reçoit les alertes de Prometheus et les route vers les bons canaux (Slack, email, PagerDuty, webhook…). Il gère aussi le groupage (éviter 100 notifications pour le même problème) et les silences (maintenance planifiée). Le fonctionnement est le suivant :

1. Prometheus évalue des règles (alert rules)
2. Si une condition est remplie → une alerte est déclenchée
3. Prometheus envoie cette alerte à Alertmanager

## Ce que fait Alertmanager

```mermaid
flowchart LR

    A["Prometheus Alerting Rules"] -->|alerts| B

    subgraph B["Alertmanager"]
        direction LR
        R["Routing"] --> G["Grouping"] --> S["Silences"] --> I["Inhibitions"]
    end

    B --> SL["Slack"]
    B --> EM["Email"]
    B --> PD["PagerDuty"]
    B --> WH["Webhook / Zapier"]

    %% Styles nodes
    classDef prom fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#000,font-weight:bold;
    classDef alert fill:#fee2e2,stroke:#dc2626,stroke-width:2px,color:#000;
    classDef output fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#000;

    %% Apply classes
    class A prom;
    class B,R,G,S,I alert;
    class SL,EM,PD,WH output;

    %% Extra styling
    style B stroke-width:3px,stroke:#b91c1c
    linkStyle default stroke:#444,stroke-width:2px
```


| Fonction        | Description                                                                 |
|-----------------|-----------------------------------------------------------------------------|
| Routing         | Envoie chaque alerte au bon destinataire selon ses labels                  |
| Grouping        | Combine plusieurs alertes similaires en une seule notification             |
| Silences        | Désactive temporairement des alertes (maintenance)                         |
| Inhibition      | Une alerte critique masque les alertes mineures liées                      |
| Déduplication   | Évite d’envoyer la même alerte plusieurs fois                              |


### Prometheus vs Alertmanager
Prometheus définit les règles d’alerte (quand déclencher).  
Alertmanager gère ce qui se passe après (où et comment notifier).  

👉 Ils fonctionnent ensemble.


## Installation d’Alertmanager
### Créer la configuration d'Alertmanager
Sur votre serveur de monitoring créer le fichier alertmanager.yml minimal : 
```yaml
global:
  resolve_timeout: 5m           # Délai avant de considérer une alerte comme résolue

route:
  group_by: ['alertname']       # Regroupe les alertes du même type en une seule notification
  group_wait: 10s               # Attente avant d'envoyer le premier groupe (laisse le temps à d'autres alertes d'arriver)
  group_interval: 10s           # Délai minimum entre deux notifications pour un même groupe
  repeat_interval: 1h           # Renvoie la notification si l'alerte est toujours active après ce délai
  receiver: 'default'           # Destinataire par défaut si aucune route spécifique ne correspond

receivers:
  - name: 'default'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/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'
        channel: '#alerts'        # Canal Slack de destination
        send_resolved: true       # Envoie aussi une notification quand l'alerte se résout
        title: '🚨 Alerte Prometheus'
        text: '{{ range .Alerts }}{{ .Annotations.summary }} - {{ .Annotations.description }}{{ end }}'
```
### Ajouter le service alertmanager.
Modifier votre fichier docker-compose.yml pour y ajouter le service alertmanager.
```yaml
  alertmanager:
    image: prom/alertmanager:v0.32.0
    container_name: alertmanager
    ports:
      - "9093:9093"                     # Interface web et API d'Alertmanager
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro  # Config montée en lecture seule
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    restart: unless-stopped
    networks:
      - monitoring
```
### Ajouter le dossier des règles pour Prometheus
Toujours dans `docker-compose.yml`, il faut monter le dossier contenant les règles d’alertes dans le conteneur Prometheus.
Dans la section `volumes` du service `prometheus`, ajouter :
```yaml
  - ./rules:/etc/prometheus/rules:ro    # Monte le dossier local rules/ dans le conteneur (lecture seule)
```

### Lancer le conteneur : 
```bash
docker compose up -d
```

Par défaut : http://localhost:9093

## Connecter Prometheus à Alertmanager

Dans `prometheus.yml`, ajouter l'emplacement des futures règles d'alertes et le lien vers notre alertmanager.
```yaml
# Chemins des fichiers de règles d'alerte à charger (glob accepté)
rule_files:
  - "rules/*.yml"

# Connexion vers Alertmanager pour lui transmettre les alertes déclenchées
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']  # Nom DNS du service Alertmanager dans le réseau Docker
```
Puis recharger la config :
```bash
curl -X POST http://localhost:9090/-/reload
```

## Création des règles d’alerte

Créer un fichier `alerts.yml` dans votre dossier `rules` :
```yaml
groups:
  - name: example-alerts              # Nom logique du groupe de règles
    rules:
      - alert: InstanceDown           # Nom de l'alerte (visible dans Prometheus et les notifications)
        expr: up == 0                 # Expression PromQL : true quand une cible ne répond plus
        for: 1m                       # La condition doit rester vraie 1 min avant de passer en Firing (évite les faux positifs)
        labels:
          severity: critical          # Label personnalisé utilisable pour le routage dans Alertmanager
        annotations:
          summary: "Instance down"
          description: "Une instance est down depuis plus de 1 minute"  # Texte inclus dans les notifications
```

## Tester une alerte

Simulez une panne :

👉 Arrêtez Node Exporter ou votre app NodeJS

Puis allez sur :

👉 http://localhost:9090/alerts

Vous devriez voir l’alerte :

- Pending → puis → Firing

## Créer des règles personalisées
Créer des règles d'alertes qui détectent :
 - CPU élevé

**Réponse :**

    - alert: HighCpuUsage
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "CPU élevé sur {{ $labels.instance }}"
        description: "L'utilisation CPU est supérieure à 80% depuis 2 minutes (valeur actuelle: {{ $value | printf \"%.1f\" }}%)"


 - Mémoire élevée

**Réponse :**

    - alert: HighMemoryUsage
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Mémoire élevée sur {{ $labels.instance }}"
        description: "L'utilisation mémoire est supérieure à 85% depuis 2 minutes (valeur actuelle: {{ $value | printf \"%.1f\" }}%)"


 - Disk usage élevé

**Réponse :**

    - alert: HighDiskUsage
      expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"})) * 100 > 85
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Disque plein sur {{ $labels.instance }} ({{ $labels.mountpoint }})"
        description: "L'occupation disque sur {{ $labels.mountpoint }} est supérieure à 85% depuis 2 minutes (valeur actuelle: {{ $value | printf \"%.1f\" }}%)"



## Conclusions

Vous avez maintenant :

- Prometheus → collecte + règles
- Alertmanager → gestion des alertes
- Un système complet de monitoring
- Les alertes sont envoyées sur un canal slack.
- On pourrait imaginer les envoyer sur un autre Webhoock ou par email.
- Il est également possible de configurer des silences (pour des périodes de maintenance par exemple).



