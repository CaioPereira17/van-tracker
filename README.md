# Van Tracker System 🚐📍

Sistema de rastreamento em tempo real para transporte de moradores, conectando motoristas e passageiros com atualizações de geolocalização ao vivo.

## 📋 Visão Geral

O projeto consiste em um ecossistema completo para gestão de transporte local:
1.  **App do Motorista:** Envia geolocalização e gerencia a rota.
2.  **Aplicação Web do Passageiro:** Visualiza a van no mapa e interage com pontos de parada.
3.  **Backend Real-time:** Gerencia a comunicação Pub/Sub via WebSockets.

## 🚀 Funcionalidades Principais

### Motorista (Mobile)
- Login seguro.
- Seleção de rota ativa.
- Envio de telemetria (GPS) em tempo real.
- **Alerta de Passageiro:** Recebe notificação visual quando um passageiro sinaliza em um ponto próximo.

### Passageiro (Web)
- Visualização da van em movimento no mapa.
- **Pontos de Parada:** Visualização dos pontos fixos da rota.
- **Sinalização Inteligente (Geofencing):** O passageiro só pode "pedir parada" se estiver dentro de um raio (ex: 50m) do ponto físico.
- Cálculo de distância estimada até a van.

## 🛠 Tecnologias

- **Mobile:** Flutter (Dart)
- **Web:** React ou Flutter Web
- **Backend:** Node.js (ou Python) + WebSockets (Socket.io)
- **Banco de Dados:** PostgreSQL (Dados fixos) + Redis (Cache de posição)
- **Mapas:** Mapbox / Leaflet / Google Maps API

## 📂 Estrutura do Projeto

- `/mobile_driver`: Código fonte do aplicativo Flutter.
- `/web_passenger`: Código fonte da aplicação Web.
- `/backend_api`: API REST e Servidor WebSocket.
- `/docs`: Documentação técnica e diagramas.

## 🚦 Status do Projeto

🚧 Em desenvolvimento inicial (Configuração de Ambiente).