import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, orderBy, limit, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';

interface AnchorData {
  id: string;
  agentId: string;
  status: 'online' | 'offline';
  battery: number;
  qodScore: number | null;
  lastUpdated: Date;
  destination?: string;
}

interface NavigatorData {
  id: string;
  agentId: string;
  status: 'online' | 'offline';
  battery: number;
  qodScore: number | null;
  lastUpdated: Date;
}

interface DistanceMeasurement {
  device_i_id: string;
  device_j_id: string;
  d_true: number;
  d_hat: number;
  e: number;
  k: number;
  timestamp: Date;
}

export function useAnchors() {
  const [anchors, setAnchors] = useState<AnchorData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(
      collection(db, 'users'),
      where('role', '==', 'Anchor')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const anchorList: AnchorData[] = [];
      
      snapshot.forEach((doc) => {
        const data = doc.data();
        const now = new Date();
        const lastActive = data.lastActive?.toDate() || new Date(0);
        const isOnline = (now.getTime() - lastActive.getTime()) < 30000; // 30 seconds
        
        anchorList.push({
          id: doc.id,
          agentId: data.destination || 'Unknown',
          status: isOnline ? 'online' : 'offline',
          battery: data.battery || 0,
          qodScore: data.qodScore || null,
          lastUpdated: lastActive,
          destination: data.destination
        });
      });

      setAnchors(anchorList);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { anchors, loading };
}

export function useNavigators() {
  const [navigators, setNavigators] = useState<NavigatorData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(
      collection(db, 'users'),
      where('role', '==', 'Navigator')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const navigatorList: NavigatorData[] = [];
      
      snapshot.forEach((doc) => {
        const data = doc.data();
        const now = new Date();
        const lastActive = data.lastActive?.toDate() || new Date(0);
        const isOnline = (now.getTime() - lastActive.getTime()) < 30000; // 30 seconds
        
        const email = data.email || doc.id;
        const username = email.split('@')[0];
        
        navigatorList.push({
          id: doc.id,
          agentId: username,
          status: isOnline ? 'online' : 'offline',
          battery: data.battery || 0,
          qodScore: data.qodScore || null,
          lastUpdated: lastActive
        });
      });

      setNavigators(navigatorList);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { navigators, loading };
}

export function useLatestSession() {
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [measurements, setMeasurements] = useState<DistanceMeasurement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Get the latest session
    const sessionsQuery = query(
      collection(db, 'distance_sessions'),
      orderBy('metadata.created_at', 'desc'),
      limit(1)
    );

    getDocs(sessionsQuery).then((snapshot) => {
      if (!snapshot.empty) {
        const latestSessionId = snapshot.docs[0].id;
        setSessionId(latestSessionId);

        // Subscribe to measurements for this session
        const measurementsQuery = query(
          collection(db, `distance_sessions/${latestSessionId}/measurements`),
          orderBy('timestamp', 'desc'),
          limit(100)
        );

        const unsubscribe = onSnapshot(measurementsQuery, (measurementSnapshot) => {
          const measurementList: DistanceMeasurement[] = [];
          
          measurementSnapshot.forEach((doc) => {
            const data = doc.data();
            measurementList.push({
              device_i_id: data.device_i_id,
              device_j_id: data.device_j_id,
              d_true: data.d_true,
              d_hat: data.d_hat,
              e: data.e,
              k: data.k,
              timestamp: data.timestamp?.toDate() || new Date()
            });
          });

          setMeasurements(measurementList);
          setLoading(false);
        });

        return () => unsubscribe();
      } else {
        setLoading(false);
      }
    });
  }, []);

  return { sessionId, measurements, loading };
}

export function calculateQoDFromMeasurements(measurements: DistanceMeasurement[]): number | null {
  if (measurements.length === 0) return null;
  
  // Calculate average normalized error (k) as QoD metric
  // Convert to a score where lower error = higher score
  const avgK = measurements.reduce((sum, m) => sum + Math.abs(m.k), 0) / measurements.length;
  
  // Convert to 0-100 score where 0% error = 100 score
  // Cap at 100% error = 0 score
  const qod = Math.max(0, Math.min(100, 100 - (avgK * 100)));
  
  return Math.round(qod);
}