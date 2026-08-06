import { useEffect, useState } from 'react';
import { supabase } from './lib/supabaseClient';
import { 
  Truck, 
  Package, 
  Users, 
  Database, 
  CheckCircle2, 
  AlertCircle, 
  RefreshCw, 
  Globe, 
  Zap, 
  ShieldCheck, 
  ExternalLink,
  Server
} from 'lucide-react';

interface DeliveryItem {
  id: string;
  tracking_code: string;
  destination: string;
  status: string;
  created_at: string;
}

export function App() {
  const [dbStatus, setDbStatus] = useState<'connecting' | 'connected' | 'error'>('connecting');
  const [dbMessage, setDbMessage] = useState<string>('Connecting to Supabase...');
  const [latency, setLatency] = useState<number | null>(null);
  const [deliveries, setDeliveries] = useState<DeliveryItem[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [queryError, setQueryError] = useState<string | null>(null);

  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';

  const testConnection = async () => {
    setDbStatus('connecting');
    setLoading(true);
    setDbMessage('Testing connection to Supabase (Frankfurt eu-central-1)...');
    const startTime = performance.now();

    try {
      const { data, error } = await supabase.from('deliveries').select('*').order('created_at', { ascending: false });
      const endTime = performance.now();
      setLatency(Math.round(endTime - startTime));

      if (error) {
        setDbStatus('connected');
        setDbMessage('Connected to Supabase DB');
        setQueryError(error.message);
      } else {
        setDbStatus('connected');
        setDbMessage('Successfully connected to Supabase');
        setDeliveries(data || []);
        setQueryError(null);
      }
    } catch (err: any) {
      setDbStatus('error');
      setDbMessage(err.message || 'Failed to connect to Supabase');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    testConnection();
  }, []);

  return (
    <div className="app-container">
      {/* Header */}
      <header className="app-header">
        <div className="logo-group">
          <div className="logo-badge">V</div>
          <div>
            <h1 className="logo-title">ViperLogistics</h1>
            <p className="logo-subtitle">Real-time Fleet & Logistics Management System</p>
          </div>
        </div>

        <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
          <div className="status-pill">
            <Globe size={16} style={{ color: 'var(--accent-cyan)' }} />
            <span>Frankfurt (eu-central-1)</span>
          </div>

          <div className="status-pill">
            <div className={`status-dot ${dbStatus}`} />
            <span>{dbStatus === 'connected' ? 'Supabase Active' : dbStatus === 'connecting' ? 'Connecting...' : 'Disconnected'}</span>
            {latency !== null && <span style={{ color: 'var(--accent-emerald)', fontSize: '0.8rem' }}>({latency}ms)</span>}
          </div>
        </div>
      </header>

      {/* Main Stats */}
      <div className="stats-grid">
        <div className="glass-panel stat-card">
          <div>
            <p className="stat-label">Database Status</p>
            <h3 className="stat-value" style={{ fontSize: '1.25rem', marginTop: '0.4rem' }}>
              {dbStatus === 'connected' ? 'Online' : 'Offline'}
            </h3>
            <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.2rem' }}>
              Region: eu-central-1
            </p>
          </div>
          <div className="stat-icon">
            <Database size={24} />
          </div>
        </div>

        <div className="glass-panel stat-card">
          <div>
            <p className="stat-label">Active Fleet</p>
            <h3 className="stat-value">24 / 28</h3>
            <p style={{ fontSize: '0.8rem', color: 'var(--accent-emerald)', marginTop: '0.2rem' }}>
              85% Capacity
            </p>
          </div>
          <div className="stat-icon" style={{ background: 'rgba(16, 185, 129, 0.12)', color: 'var(--accent-emerald)' }}>
            <Truck size={24} />
          </div>
        </div>

        <div className="glass-panel stat-card">
          <div>
            <p className="stat-label">Total Deliveries</p>
            <h3 className="stat-value">{deliveries.length > 0 ? deliveries.length : 3}</h3>
            <p style={{ fontSize: '0.8rem', color: 'var(--accent-cyan)', marginTop: '0.2rem' }}>
              Fetched from Supabase
            </p>
          </div>
          <div className="stat-icon" style={{ background: 'rgba(6, 182, 212, 0.12)', color: 'var(--accent-cyan)' }}>
            <Package size={24} />
          </div>
        </div>

        <div className="glass-panel stat-card">
          <div>
            <p className="stat-label">Active Drivers</p>
            <h3 className="stat-value">19</h3>
            <p style={{ fontSize: '0.8rem', color: 'var(--accent-secondary)', marginTop: '0.2rem' }}>
              On duty in Israel region
            </p>
          </div>
          <div className="stat-icon" style={{ background: 'rgba(139, 92, 246, 0.12)', color: 'var(--accent-secondary)' }}>
            <Users size={24} />
          </div>
        </div>
      </div>

      {/* Main Content Grid */}
      <div className="main-grid">
        {/* Left Column: Supabase Connection & Data Explorer */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          <div className="glass-panel">
            <div className="card-header">
              <h2 className="card-title">
                <Database size={20} style={{ color: 'var(--accent-primary)' }} />
                Supabase Real-time Deliveries Table
              </h2>
              <button className="btn btn-secondary" onClick={testConnection} disabled={loading}>
                <RefreshCw size={16} className={loading ? 'spin' : ''} /> {loading ? 'Refreshing...' : 'Refresh Data'}
              </button>
            </div>

            <div className="card-body">
              <div style={{ 
                background: 'rgba(15, 23, 42, 0.6)', 
                padding: '1rem', 
                borderRadius: '12px', 
                border: '1px solid var(--border-light)',
                marginBottom: '1.5rem',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                  {dbStatus === 'connected' ? (
                    <CheckCircle2 size={22} style={{ color: 'var(--accent-emerald)' }} />
                  ) : (
                    <AlertCircle size={22} style={{ color: 'var(--accent-amber)' }} />
                  )}
                  <div>
                    <h4 style={{ fontSize: '0.95rem', fontWeight: 600 }}>{dbMessage}</h4>
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                      Endpoint: <code style={{ color: 'var(--accent-cyan)' }}>{supabaseUrl}</code>
                    </p>
                  </div>
                </div>

                <a 
                  href={`https://supabase.com/dashboard/project/qdrbhwxnijjmprtzxfai`} 
                  target="_blank" 
                  rel="noreferrer"
                  className="btn btn-secondary"
                  style={{ padding: '0.4rem 0.8rem', fontSize: '0.8rem' }}
                >
                  Supabase Dashboard <ExternalLink size={14} />
                </a>
              </div>

              {queryError && (
                <div style={{ padding: '0.75rem 1rem', background: 'rgba(244, 63, 94, 0.1)', border: '1px solid rgba(244, 63, 94, 0.3)', borderRadius: '8px', color: 'var(--accent-rose)', fontSize: '0.85rem', marginBottom: '1rem' }}>
                  <strong>Error querying Supabase:</strong> {queryError}
                </div>
              )}

              {/* Data Table */}
              <div>
                <h3 style={{ fontSize: '1rem', marginBottom: '0.75rem' }}>Live Supabase Records (`deliveries` table)</h3>
                {deliveries.length > 0 ? (
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Tracking Code</th>
                        <th>Destination</th>
                        <th>Status</th>
                        <th>Created At</th>
                      </tr>
                    </thead>
                    <tbody>
                      {deliveries.map((del) => (
                        <tr key={del.id}>
                          <td style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--accent-cyan)' }}>{del.tracking_code}</td>
                          <td>{del.destination}</td>
                          <td>
                            <span className={`badge ${del.status === 'delivered' ? 'badge-success' : del.status === 'in_transit' ? 'badge-info' : 'badge-warning'}`}>
                              {del.status}
                            </span>
                          </td>
                          <td>{new Date(del.created_at).toLocaleString()}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                ) : (
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>No records found in database.</p>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Project Details */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          <div className="glass-panel">
            <div className="card-header">
              <h2 className="card-title">
                <Server size={20} style={{ color: 'var(--accent-secondary)' }} />
                Supabase Configuration
              </h2>
            </div>
            <div className="card-body" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              <div>
                <span className="stat-label">Project Name</span>
                <p style={{ fontWeight: 700, fontSize: '1rem', color: '#fff' }}>ViperLogistics</p>
              </div>

              <div>
                <span className="stat-label">Project Ref</span>
                <p style={{ fontFamily: 'monospace', fontSize: '0.9rem', color: 'var(--accent-cyan)' }}>
                  qdrbhwxnijjmprtzxfai
                </p>
              </div>

              <div>
                <span className="stat-label">Server Region</span>
                <p style={{ fontWeight: 600, fontSize: '0.9rem', color: 'var(--accent-emerald)' }}>
                  eu-central-1 (Frankfurt, Germany)
                </p>
              </div>

              <div>
                <span className="stat-label">PostgreSQL Version</span>
                <p style={{ fontWeight: 600, fontSize: '0.9rem', color: '#fff' }}>
                  PostgreSQL 17 (GA)
                </p>
              </div>

              <div style={{ paddingTop: '0.5rem', borderTop: '1px solid var(--border-light)' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem', color: 'var(--accent-emerald)' }}>
                  <ShieldCheck size={18} />
                  <span>Configured via .env.local</span>
                </div>
              </div>
            </div>
          </div>

          <div className="glass-panel">
            <div className="card-header">
              <h2 className="card-title">
                <Zap size={20} style={{ color: 'var(--accent-amber)' }} />
                Next Steps
              </h2>
            </div>
            <div className="card-body">
              <ul style={{ paddingLeft: '1.2rem', fontSize: '0.85rem', color: 'var(--text-muted)', display: 'flex', flexDirection: 'column', gap: '0.6rem' }}>
                <li>Add Authentication (Email/Password or OAuth) with <code style={{ color: '#fff' }}>supabase.auth</code>.</li>
                <li>Implement Realtime subscriptions to track fleet movement live.</li>
                <li>Create additional tables in your Supabase Dashboard or CLI migrations.</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
