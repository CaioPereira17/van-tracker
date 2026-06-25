import React, { useEffect, useState, useMemo } from 'react';
import { GoogleMap, LoadScript, OverlayView, Marker } from '@react-google-maps/api';
import io from 'socket.io-client';
import vanIconImg from './assets/van1.png';


// Se for usar IP direto na VPS, garanta que a porta 3000 esteja liberada.
const socket = io(import.meta.env.VITE_MEU_IP);

const containerStyle = { width: '100vw', height: '100vh' };
// Centro padrão (Rio de Janeiro) caso o usuário não dê permissão de GPS
const CENTRO_INICIAL = { lat: -22.931173, lng: -43.179873 };

// --- ESTILOS DO MAPA ---
const MAP_LIGHT = [
    { "featureType": "poi", "stylers": [{ "visibility": "off" }] },
    { "featureType": "transit", "stylers": [{ "visibility": "off" }] }
];

const MAP_DARK = [
    { "elementType": "geometry", "stylers": [{ "color": "#242f3e" }] },
    { "elementType": "labels.text.stroke", "stylers": [{ "color": "#242f3e" }] },
    { "elementType": "labels.text.fill", "stylers": [{ "color": "#746855" }] },
    { "featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{ "color": "#d59563" }] },
    { "featureType": "poi", "elementType": "labels.text.fill", "stylers": [{ "color": "#d59563" }] },
    { "featureType": "poi.park", "elementType": "geometry", "stylers": [{ "color": "#263c3f" }] },
    { "featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{ "color": "#6b9a76" }] },
    { "featureType": "road", "elementType": "geometry", "stylers": [{ "color": "#38414e" }] },
    { "featureType": "road", "elementType": "geometry.stroke", "stylers": [{ "color": "#212a37" }] },
    { "featureType": "road", "elementType": "labels.text.fill", "stylers": [{ "color": "#9ca5b3" }] },
    { "featureType": "road.highway", "elementType": "geometry", "stylers": [{ "color": "#746855" }] },
    { "featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{ "color": "#1f2835" }] },
    { "featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{ "color": "#f3d19c" }] },
    { "featureType": "water", "elementType": "geometry", "stylers": [{ "color": "#17263c" }] },
    { "featureType": "water", "elementType": "labels.text.fill", "stylers": [{ "color": "#515c6d" }] },
    { "featureType": "water", "elementType": "labels.text.stroke", "stylers": [{ "color": "#17263c" }] }
];

// --- FUNÇÕES MATEMÁTICAS ---
function deg2rad(deg) { return deg * (Math.PI / 180); }
function toDeg(rad) { return rad * 180 / Math.PI; }

function getHeading(lat1, lng1, lat2, lng2) {
    const dLon = deg2rad(lng2 - lng1);
    const y = Math.sin(dLon) * Math.cos(deg2rad(lat2));
    const x = Math.cos(deg2rad(lat1)) * Math.sin(deg2rad(lat2)) -
              Math.sin(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.cos(dLon);
    const brng = toDeg(Math.atan2(y, x));
    return (brng + 360) % 360;
}

function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = deg2rad(parseFloat(lat2) - parseFloat(lat1));
    const dLon = deg2rad(parseFloat(lon2) - parseFloat(lon1));
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return (R * c).toFixed(1);
}

// Offset para centralizar ícone de 50px
const getPixelPositionOffset = () => ({ x: -25, y: -25 });

function App() {
    // --- ESTADOS ---
    const [vans, setVans] = useState({});
    const [activeVanId, setActiveVanId] = useState(null);
    const [mapRef, setMapRef] = useState(null);
    const [darkMode, setDarkMode] = useState(false);
    
    // Estados de Localização
    const [userLocation, setUserLocation] = useState(null);
    const [gpsError, setGpsError] = useState(null);

    const theme = {
        cardBg: darkMode ? '#2c3e50' : 'white',
        text: darkMode ? '#ecf0f1' : '#2c3e50',
        subText: darkMode ? '#bdc3c7' : '#7f8c8d'
    };

    const mapOptions = useMemo(() => ({
        disableDefaultUI: true,
        zoomControl: false,
        clickableIcons: false,
        styles: darkMode ? MAP_DARK : MAP_LIGHT
    }), [darkMode]);

    // --- 1. GPS DO USUÁRIO (VERSÃO FINAL) ---
    useEffect(() => {
        if (!navigator.geolocation) {
            // Navegador muito antigo
            setTimeout(() => setGpsError("Seu navegador não suporta GPS."), 0);
            return;
        }

        navigator.geolocation.getCurrentPosition(
            (position) => {
                // Sucesso: Salva a localização real
                setUserLocation({ 
                    lat: position.coords.latitude, 
                    lng: position.coords.longitude 
                });
                setGpsError(null);
            },
            (error) => {
                // Erro: Não define localização falsa. Apenas avisa.
                let msg = "Não foi possível obter sua localização.";
                if (error.code === 1) msg = "Permissão de localização negada.";
                else if (error.code === 2) msg = "Sinal de GPS indisponível.";
                else if (error.code === 3) msg = "Tempo limite de GPS esgotado.";

                // Usamos setTimeout para evitar erro de renderização do React
                setTimeout(() => setGpsError(msg), 0);
            },
            { 
                enableHighAccuracy: true, 
                timeout: 10000, 
                maximumAge: 0 
            }
        );
    }, []);

    // --- 2. SOCKETS ---
    useEffect(() => {
        socket.on('current_active_vans', (lista) => {
            const novoEstado = {};
            lista.forEach(v => { novoEstado[v.van_id] = { ...v, heading: 0 }; });
            setVans(novoEstado);
        });

        socket.on('van_location_updated', (data) => {
            setVans((prevVans) => {
                const oldData = prevVans[data.van_id];
                let newHeading = oldData ? oldData.heading : 0;

                if (oldData) {
                    const dist = Math.sqrt(Math.pow(data.lat - oldData.lat, 2) + Math.pow(data.lng - oldData.lng, 2));
                    if (dist > 0.00001) {
                        newHeading = getHeading(oldData.lat, oldData.lng, data.lat, data.lng);
                    }
                }
                return { ...prevVans, [data.van_id]: { ...data, heading: newHeading } };
            });
        });

        socket.on('van_disconnected', (data) => {
            setVans((prev) => {
                const copy = { ...prev };
                delete copy[data.van_id];
                return copy;
            });
            if (activeVanId === data.van_id) setActiveVanId(null);
        });

        return () => {
            socket.off('van_location_updated');
            socket.off('van_disconnected');
            socket.off('current_active_vans');
        };
    }, [activeVanId]);

    // --- 3. CÂMERA ---
    useEffect(() => {
        if (!activeVanId || !mapRef || !vans[activeVanId]) return;
        const vanAtiva = vans[activeVanId];
        mapRef.panTo({ lat: vanAtiva.lat, lng: vanAtiva.lng });
    }, [vans, activeVanId, mapRef]);

    const handleFocusVan = (id) => {
        if (activeVanId === id) {
            setActiveVanId(null);
        } else {
            setActiveVanId(id);
            if (vans[id] && mapRef) {
                mapRef.setZoom(18);
                mapRef.panTo({ lat: vans[id].lat, lng: vans[id].lng });
            }
        }
    };

    return (
        <LoadScript googleMapsApiKey={import.meta.env.VITE_GOOGLE_API_KEY}>

            {/* BOTÃO DARK MODE */}
            <button onClick={() => setDarkMode(!darkMode)} style={{
                position: 'absolute', top: 15, right: 15, zIndex: 2000,
                background: darkMode ? '#f1c40f' : '#2c3e50', color: darkMode ? '#333' : 'white',
                border: 'none', borderRadius: '50%', width: 40, height: 40, fontSize: '20px',
                cursor: 'pointer', boxShadow: '0 2px 5px rgba(0,0,0,0.3)'
            }}>
                {darkMode ? '☀' : '☾'}
            </button>

            {/* AVISO GPS (Só aparece se der erro real) */}
            {gpsError && (
                <div style={{
                    position: 'absolute', bottom: 20, left: '50%', transform: 'translateX(-50%)',
                    zIndex: 2000, background: '#e74c3c', color: 'white', padding: '10px',
                    borderRadius: 8, fontSize: '12px', fontWeight: 'bold'
                }}>
                    ⚠️ {gpsError}
                </div>
            )}

            {/* PAINEL LATERAL */}
            <div style={{
                position: 'absolute', top: 10, left: 10, zIndex: 1000,
                display: 'flex', flexDirection: 'column', gap: 10, alignItems: 'flex-start',
                width: '90%', maxWidth: '350px'
            }}>
                <div style={{
                    background: theme.cardBg, padding: '15px 20px', borderRadius: 12,
                    boxShadow: '0 4px 12px rgba(0,0,0,0.2)', width: '100%', boxSizing: 'border-box',
                    transition: 'background 0.3s'
                }}>
                    <h2 style={{ margin: 0, fontSize: '1.2rem', fontFamily: 'Segoe UI, sans-serif', color: theme.text }}>
                        🚐 Frota Online
                    </h2>
                    <p style={{ margin: '5px 0 0 0', color: '#27ae60', fontWeight: 'bold', fontSize: '0.9rem' }}>
                        {Object.keys(vans).length} motorista(s) ativo(s)
                    </p>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: '100%', maxHeight: '50vh', overflowY: 'auto', paddingBottom: 10 }}>
                    {Object.values(vans).map((van) => {
                        const isLunching = van.status === 'lunch';
                        const displayName = van.driver_name || `Van ${van.van_id ? van.van_id.substr(0, 4) : '...'}`;

                        // Cálculo de distância (Só calcula se tiver GPS real)
                        let distanceText = "";
                        if (userLocation) {
                            const km = getDistanceFromLatLonInKm(userLocation.lat, userLocation.lng, van.lat, van.lng);
                            distanceText = ` • ${km} km de você`;
                        }

                        return (
                            <div key={van.van_id} style={{
                                background: theme.cardBg,
                                padding: '10px 15px', borderRadius: 8, boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
                                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                                transition: 'background 0.3s',
                                borderLeft: isLunching ? '5px solid orange' : (activeVanId === van.van_id ? '5px solid #2ecc71' : '5px solid #bdc3c7')
                            }}>
                                <div style={{ overflow: 'hidden', marginRight: 10 }}>
                                    <strong style={{ fontFamily: 'Segoe UI, sans-serif', display: 'block', color: theme.text, whiteSpace: 'nowrap', textOverflow: 'ellipsis', overflow: 'hidden' }}>
                                        {displayName}
                                    </strong>
                                    <span style={{ fontSize: '0.8rem', color: isLunching ? 'orange' : theme.subText, fontWeight: isLunching ? 'bold' : 'normal' }}>
                                        {isLunching ? 'Almoçando' : (activeVanId === van.van_id ? 'Seguindo' : 'Em rota')}
                                        <span style={{ color: '#3498db', fontWeight: 'bold', fontSize: '0.75rem', display: 'block', marginTop: 2 }}>
                                            {!isLunching && (distanceText || (gpsError ? "" : "• Calculando..."))}
                                        </span>
                                    </span>
                                </div>

                                <button
                                    onClick={() => handleFocusVan(van.van_id)}
                                    disabled={isLunching}
                                    style={{
                                        background: isLunching ? '#ccc' : (activeVanId === van.van_id ? '#e74c3c' : '#3498db'),
                                        color: 'white', border: 'none', padding: '8px 12px', borderRadius: '6px',
                                        cursor: isLunching ? 'not-allowed' : 'pointer', fontWeight: 'bold', fontSize: '0.75rem', minWidth: '60px'
                                    }}
                                >
                                    {isLunching ? 'PAUSA' : (activeVanId === van.van_id ? 'PARAR' : 'VER')}
                                </button>
                            </div>
                        );
                    })}
                </div>

                {/* Card de Distância Flutuante (apenas se seguindo uma van e com GPS ativo) */}
                {activeVanId && vans[activeVanId] && userLocation && (
                    <div style={{
                        background: '#3498db', color: 'white', padding: '10px 15px',
                        borderRadius: 12, boxShadow: '0 4px 15px rgba(0,0,0,0.2)', minWidth: '200px',
                        animation: 'fadeIn 0.5s'
                    }}>
                        <strong style={{ fontFamily: 'Segoe UI, sans-serif', fontSize: '0.75rem', opacity: 0.9, textTransform: 'uppercase' }}>Distância até a van</strong><br />
                        <div style={{ fontSize: '1.2rem', fontFamily: 'Segoe UI, sans-serif', fontWeight: 600, marginTop: 2 }}>
                            📍 {getDistanceFromLatLonInKm(userLocation.lat, userLocation.lng, vans[activeVanId].lat, vans[activeVanId].lng)} km
                        </div>
                    </div>
                )}
            </div>

            {/* MAPA */}
            <GoogleMap
                mapContainerStyle={containerStyle}
                // Se tiver localização do usuário, centra nele. Se não, centra no Rio (padrão)
                center={userLocation || CENTRO_INICIAL}
                zoom={15}
                options={mapOptions}
                onLoad={(map) => setMapRef(map)}
                onDragStart={() => { if (activeVanId) setActiveVanId(null); }}
            >
                {/* Marcador do Usuário (Só aparece se tiver GPS real) */}
                {userLocation && (
                    <Marker
                        position={userLocation}
                        icon={{
                            path: window.google.maps.SymbolPath.CIRCLE, scale: 8, fillColor: "#4285F4",
                            fillOpacity: 1, strokeColor: "white", strokeWeight: 2,
                        }}
                    />
                )}

                {/* Vans */}
                {Object.values(vans).map((van) => (
                    <OverlayView
                        key={van.van_id}
                        position={{ lat: van.lat, lng: van.lng }}
                        mapPaneName={OverlayView.OVERLAY_MOUSE_TARGET}
                        getPixelPositionOffset={getPixelPositionOffset}
                    >
                        <div
                            style={{
                                width: '50px', height: '50px',
                                display: 'flex', justifyContent: 'center', alignItems: 'center',
                                transform: `rotate(${van.heading - 90}deg)`,
                                transformOrigin: 'center center',
                                transition: 'transform 0.3s ease-out',
                                cursor: 'pointer', position: 'relative'
                            }}
                            onClick={() => handleFocusVan(van.van_id)}
                        >
                            <img src={vanIconImg} style={{ width: '100%', height: '100%', objectFit: 'contain' }} alt="van" />
                            <div style={{
                                position: 'absolute', top: -35, left: '50%',
                                transform: `translateX(-50%) rotate(-${van.heading - 90}deg)`,
                                background: 'white', color: '#333', padding: '2px 8px', borderRadius: 4,
                                fontSize: '11px', whiteSpace: 'nowrap', fontWeight: 'bold',
                                boxShadow: '0 2px 4px rgba(0,0,0,0.3)', border: '1px solid #ddd', zIndex: 9999
                            }}>
                                {van.driver_name}
                            </div>
                        </div>
                    </OverlayView>
                ))}
            </GoogleMap>
        </LoadScript>
    );
}

export default App;