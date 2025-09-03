import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: "AIzaSyDbqQN6EfF83Pzv9K4LcAGBnmhHKhJ1QQc",
  authDomain: "uwbnavigator-2ba08.firebaseapp.com",
  projectId: "uwbnavigator-2ba08",
  storageBucket: "uwbnavigator-2ba08.firebasestorage.app",
  messagingSenderId: "838453486062",
  appId: "1:838453486062:ios:adbc967e3f6fb1e51e87fa"
};

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);