const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const PORT = process.env.PORT || 3000;

const io = new Server(server, {
    cors: { origin: "*", methods: ["GET", "POST"] }
});

let activeVans = {};

io.on('connection', (socket) => {
    console.log(`🔌 Conectado: ${socket.id}`);

    socket.emit('current_active_vans', Object.values(activeVans));

    socket.on('update_location', (data) => {
        // Guarda o socket.id dentro do objeto para facilitar a remoção
        activeVans[socket.id] = { ...data, socket_id: socket.id };
        io.emit('van_location_updated', activeVans[socket.id]);
    });

    // 🚀 NOVO COMANDO: O motorista clicou em "Encerrar"
    socket.on('stop_run', (data) => {
        console.log(`🛑 Van encerrou expediente: ${data.van_id}`);
        // Remove da lista
        delete activeVans[socket.id];
        // Avisa o front para remover o ícone
        io.emit('van_disconnected', { van_id: data.van_id });
    });

    socket.on('disconnect', () => {
        if (activeVans[socket.id]) {
            const vanQueSaiu = activeVans[socket.id];
            console.log(`❌ Van desconectou (Sinal perdido): ${vanQueSaiu.van_id}`);
            io.emit('van_disconnected', { van_id: vanQueSaiu.van_id });
            delete activeVans[socket.id];
        }
    });
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🔥 Servidor Frota rodando na porta ${PORT}`);
});