# tommynotes
Domingo Virtual Notes


CREATE TABLE main (
  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  data TEXT NOT NULL,
  binary BLOB NULL,
  author VARCHAR(64) NOT NULL DEFAULT '',
  client VARCHAR(255) NOT NULL DEFAULT '',
  date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  colour INTEGER NOT NULL DEFAULT 16777215,
  is_visible BOOLEAN NOT NULL DEFAULT true,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  is_deleted BOOLEAN NOT NULL DEFAULT false
);
