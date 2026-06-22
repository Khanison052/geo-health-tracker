const { Pool } = require('pg');
const hosts = ['localhost', '127.0.0.1'];
(async () => {
  for (const host of hosts) {
    const pool = new Pool({ host, port: 5432, user: 'postgres', password: 'Wit03072003', database: 'postgres', max: 1 });
    try {
      console.log('Testing', host);
      const res = await pool.query('SELECT 1');
      console.log('SUCCESS', host, res.rows);
    } catch (err) {
      console.error('FAIL', host, err.code, err.message);
    } finally {
      await pool.end();
    }
  }
})();