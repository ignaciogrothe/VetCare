-- Esquema de la API de la clinica veterinaria (Caso 2).
-- Uso: mysql -u root -p < sql/schema.sql

CREATE DATABASE IF NOT EXISTS veterinaria
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE veterinaria;

CREATE TABLE IF NOT EXISTS usuarios (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  email VARCHAR(254) NOT NULL,
  clave_hash VARCHAR(100) NOT NULL,
  rol ENUM('dueno', 'veterinario', 'recepcionista', 'administrador') NOT NULL,
  telefono VARCHAR(15) NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE KEY uq_usuarios_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS mascotas (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL,
  especie ENUM('perro', 'gato', 'ave', 'conejo', 'otro') NOT NULL,
  sexo ENUM('macho', 'hembra') NOT NULL,
  fecha_nacimiento DATE NULL,
  peso_kg DECIMAL(5, 2) NULL,
  dueno_id INT UNSIGNED NOT NULL,
  CONSTRAINT fk_mascotas_dueno FOREIGN KEY (dueno_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS citas (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  mascota_id INT UNSIGNED NOT NULL,
  veterinario_id INT UNSIGNED NOT NULL,
  fecha_hora DATETIME NOT NULL,
  motivo VARCHAR(200) NOT NULL,
  estado ENUM('agendada', 'atendida', 'cancelada') NOT NULL DEFAULT 'agendada',
  -- Solo vale fecha_hora mientras la cita esta agendada: el indice unico impide
  -- que un veterinario tenga dos citas agendadas a la misma hora (409), incluso
  -- si dos peticiones llegan al mismo tiempo. Las canceladas no bloquean el bloque.
  bloque_agendado DATETIME AS (IF(estado = 'agendada', fecha_hora, NULL)) STORED,
  UNIQUE KEY uq_citas_veterinario_bloque (veterinario_id, bloque_agendado),
  KEY ix_citas_fecha (fecha_hora),
  CONSTRAINT fk_citas_mascota FOREIGN KEY (mascota_id)
    REFERENCES mascotas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_citas_veterinario FOREIGN KEY (veterinario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS atenciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cita_id INT UNSIGNED NOT NULL,
  diagnostico TEXT NOT NULL,
  tratamiento TEXT NULL,
  fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_atenciones_cita (cita_id),
  CONSTRAINT fk_atenciones_cita FOREIGN KEY (cita_id)
    REFERENCES citas (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS recetas (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  atencion_id INT UNSIGNED NOT NULL,
  medicamento VARCHAR(80) NOT NULL,
  dosis VARCHAR(100) NOT NULL,
  duracion_dias SMALLINT UNSIGNED NOT NULL,
  CONSTRAINT fk_recetas_atencion FOREIGN KEY (atencion_id)
    REFERENCES atenciones (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- El primer administrador lo crea el servidor al arrancar (ver README),
-- porque la clave debe guardarse como hash bcrypt.
