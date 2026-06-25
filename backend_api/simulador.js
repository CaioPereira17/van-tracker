// backend_api/simulador.js
const io = require('socket.io-client');

// CONECTA NO SEU SERVIDOR LOCAL
// Se seu servidor estiver em outra porta, mude aqui
const socket = io('http://localhost:3000'); 

const VAN_ID = "VAN_ROBO_01";
const ROTA = [
    { lat: -22.932640, lng: -43.185935 }, // Ponto 1
    { lat: -22.931520, lng: -43.186450 }, // Ponto 2
    { lat: -22.930523, lng: -43.187826 }, // Ponto 3
    { lat: -22.930666, lng: -43.188506 }, // Ponto 4
    { lat: -22.930881, lng: -43.189942 }, // Ponto 6
    { lat: -22.931173, lng: -43.179873 }  // Largo do Machado
];

let indiceAtual = 0;

console.log("🤖 Iniciando Motorista Robô...");

socket.on('connect', () => {
    console.log(`✅ Robô ${VAN_ID} conectado ao servidor!`);
    andar();
});

function andar() {
    if (!socket.connected) return;

    const ponto = ROTA[indiceAtual];

    // Simula um pouco de "tremecilique" no GPS para parecer real
    const latReal = ponto.lat + (Math.random() * 0.0001);
    const lngReal = ponto.lng + (Math.random() * 0.0001);

    const dados = {
        van_id: VAN_ID,
        lat: latReal,
        lng: lngReal,
        timestamp: new Date().toISOString()
    };

    socket.emit('update_location', dados);
    console.log(`📡 Enviando: ${VAN_ID} -> [${latReal.toFixed(5)}, ${lngReal.toFixed(5)}]`);

    // Avança para o próximo ponto da rota (vai e volta)
    indiceAtual = (indiceAtual + 1) % ROTA.length;

    // Envia a cada 2 segundos
    setTimeout(andar, 2000);
}