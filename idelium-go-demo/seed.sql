-- Local Go-only demo administrator. The password is the documented synthetic
-- demo value: admin. This file is disposable and is never used in production.
INSERT INTO users (id, name, email, password, role, idCostumer, status)
VALUES (
  9002,
  'Go Demo Administrator',
  'admin@idelium.org',
  '$2y$12$huvhpW4phykxt5MYmPNrletEssmNbfs4CaLnM5hiMIlDm1h4UByoq',
  1,
  9001,
  'active'
);
