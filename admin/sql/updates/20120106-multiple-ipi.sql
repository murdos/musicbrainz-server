BEGIN;

-- ipi

CREATE TABLE ipi
(
    id                  SERIAL,
    ipi            VARCHAR(11)
);

ALTER TABLE ipi ADD CONSTRAINT ipi_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX ipi_idx_ipi ON ipi (ipi);

INSERT INTO ipi (ipi)
	SELECT DISTINCT ipi_code FROM artist WHERE ipi_code IS NOT NULL
	UNION
	SELECT DISTINCT ipi_code FROM label WHERE ipi_code IS NOT NULL;

-- artist_ipi

CREATE TABLE artist_ipi
(
    artist              INTEGER NOT NULL, -- PK, references artist.id
    ipi                 INTEGER NOT NULL, -- PK, references ipi.id
    edits_pending       INTEGER NOT NULL DEFAULT 0 CHECK (edits_pending >= 0),
    created             TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE artist_ipi ADD CONSTRAINT artist_ipi_pkey PRIMARY KEY (artist, ipi);

ALTER TABLE artist_ipi
   ADD CONSTRAINT artist_ipi_fk_artist
   FOREIGN KEY (artist)
   REFERENCES artist(id);

ALTER TABLE artist_ipi
   ADD CONSTRAINT artist_ipi_fk_ipi
   FOREIGN KEY (ipi)
   REFERENCES ipi(id);

INSERT INTO artist_ipi (artist, ipi)
	SELECT artist.id, ipi.id
	FROM artist
	JOIN ipi ON ipi.ipi = artist.ipi_code;

--ALTER TABLE artist DROP COLUMN ipi_code;

-- label_ipi

CREATE TABLE label_ipi
(
    label               INTEGER NOT NULL, -- PK, references label.id
    ipi                 INTEGER NOT NULL, -- PK, references ipi.id
    edits_pending       INTEGER NOT NULL DEFAULT 0 CHECK (edits_pending >= 0),
    created             TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE label_ipi ADD CONSTRAINT label_ipi_pkey PRIMARY KEY (label, ipi);

ALTER TABLE label_ipi
   ADD CONSTRAINT label_ipi_fk_label
   FOREIGN KEY (label)
   REFERENCES label(id);

ALTER TABLE label_ipi
   ADD CONSTRAINT label_ipi_fk_ipi
   FOREIGN KEY (ipi)
   REFERENCES ipi(id);

INSERT INTO label_ipi (label, ipi)
	SELECT label.id, ipi.id
	FROM label
	JOIN ipi ON ipi.ipi = label.ipi_code;

--ALTER TABLE label DROP COLUMN ipi_code;

COMMIT;
