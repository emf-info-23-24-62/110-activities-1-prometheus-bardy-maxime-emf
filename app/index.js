const express = require('express');
const client = require('prom-client');

const app = express();
const port = 3000;

const register = new client.Registry();

register.setDefaultLabels({
  app: 'node-metrics-demo',
});

client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Nombre total de requêtes HTTP reçues',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDurationSeconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Durée des requêtes HTTP en secondes',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

const appErrorsTotal = new client.Counter({
  name: 'app_errors_total',
  help: 'Nombre total d erreurs applicatives',
  labelNames: ['route', 'type'],
  registers: [register],
});

const activeUsers = new client.Gauge({
  name: 'app_active_users',
  help: 'Nombre d utilisateurs actifs simulés',
  registers: [register],
});

const ordersCreatedTotal = new client.Counter({
  name: 'orders_created_total',
  help: 'Nombre total de commandes creees',
  labelNames: ['status'],
  registers: [register],
});

const orderAmountEuros = new client.Histogram({
  name: 'order_amount_euros',
  help: 'Distribution du montant des commandes en euros',
  buckets: [10, 20, 50, 100, 200, 500, 1000],
  registers: [register],
});

app.use((req, res, next) => {
  const end = httpRequestDurationSeconds.startTimer();

  res.on('finish', () => {
    const route = req.route?.path || req.path || 'unknown';
    const statusCode = res.statusCode.toString();

    httpRequestsTotal.inc({
      method: req.method,
      route,
      status_code: statusCode,
    });

    end({
      method: req.method,
      route,
      status_code: statusCode,
    });
  });

  next();
});

app.get('/', (req, res) => {
  res.send('Hello World avec metrics');
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/slow', (req, res) => {
  const delay = Math.floor(Math.random() * 1500) + 300;

  setTimeout(() => {
    res.json({
      message: 'Réponse lente simulée',
      delay_ms: delay,
    });
  }, delay);
});

app.get('/error', (req, res) => {
  appErrorsTotal.inc({
    route: '/error',
    type: 'simulated_error',
  });

  res.status(500).json({
    error: 'Erreur simulée pour Prometheus',
  });
});

app.post('/orders', (req, res) => {
  const amount = Math.floor(Math.random() * 500) + 20;
  const success = Math.random() > 0.2;

  orderAmountEuros.observe(amount);

  if (success) {
    ordersCreatedTotal.inc({ status: 'success' });
    return res.status(201).json({
      message: 'Commande créée',
      amount,
      status: 'success',
    });
  }

  ordersCreatedTotal.inc({ status: 'failed' });
  appErrorsTotal.inc({
    route: '/orders',
    type: 'order_creation_failed',
  });

  return res.status(500).json({
    message: 'Echec de création de commande',
    amount,
    status: 'failed',
  });
});

app.get('/users', (req, res) => {
  const simulatedUsers = Math.floor(Math.random() * 100) + 1;
  activeUsers.set(simulatedUsers);

  res.json({
    active_users: simulatedUsers,
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.listen(port, () => {
  console.log(`Application disponible sur http://localhost:${port}`);
  console.log(`Metrics disponibles sur http://localhost:${port}/metrics`);
});
