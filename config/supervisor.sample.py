"""Supervisor Configuration (Gunicorn-style Python config)."""

bind = "0.0.0.0:8000"
workers = 4
worker_class = "gthread"
threads = 4
timeout = 30.0
graceful_timeout = 30.0
app_uri = "web.server:app"
manage_database = True
