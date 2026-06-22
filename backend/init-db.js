const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const baseConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
};

const defaultDb = process.env.DB_DEFAULT_DATABASE || 'postgres';
const targetDb = process.env.DB_NAME || 'geohealth';
const schemaPath = path.join(__dirname, 'schema.sql');

async function run() {
  const adminPool = new Pool({
    ...baseConfig,
    database: defaultDb,
  });

  try {
    const exists = await adminPool.query(
      `SELECT 1 FROM pg_database WHERE datname = $1`,
      [targetDb]
    );

    if (exists.rowCount === 0) {
      console.log(`Creating database ${targetDb}...`);
      await adminPool.query(`CREATE DATABASE ${targetDb}`);
    } else {
      console.log(`Database ${targetDb} already exists.`);
    }
  } finally {
    await adminPool.end();
  }

  const dbPool = new Pool({
    ...baseConfig,
    database: targetDb,
  });

  try {
    const schema = fs.readFileSync(schemaPath, 'utf8');
    console.log(`Applying schema from ${schemaPath}...`);
    await dbPool.query(schema);
    console.log('Schema applied successfully.');
  } finally {
    await dbPool.end();
  }
}

run().catch((error) => {
  console.error('Failed to initialize database:', error);
  process.exit(1);
});
