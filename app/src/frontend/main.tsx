import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/shells.css';
import './styles/courts.css';
import './styles/booking.css';
import './styles/history.css';
import './styles/manager-bookings.css';
import './styles/manager-courts.css';
import './styles/notifications.css';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { AuthProvider } from './auth/AuthContext';
import { App } from './App';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </BrowserRouter>
  </React.StrictMode>,
);