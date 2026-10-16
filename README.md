<div align="center">

  <h1>🏎️ Retro Racing</h1>
  
  <p>
    <strong>Jogo de corrida top-down 2D desenvolvido com Flutter & Flame Engine</strong>
  </p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Flame_Engine-E64A19?style=for-the-badge&logo=flame&logoColor=white" alt="Flame" />
    <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop-green?style=for-the-badge" alt="Platform" />
    <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License" />
  </p>

  <p>
    Física vetorial realista com sistema de <em>drift</em>, resposta de áudio dinâmico de motor e feedback tátil por vibração.
  </p>

</div>

<hr />

<h2>✨ Destaques do Projeto</h2>

<ul>
  <li><strong>Física Vetorial e Derrapagem (Drift):</strong> Decomposição vetorial de tração linear e velocidade lateral (<em>slip</em>). O freio de mão reduz a aderência e gera marcas de borracha contínuas (<em>skid marks</em>) no asfalto.</li>
  <li><strong>Colisão com Barreira (SDF):</strong> Deteção de bordas e <em>guard-rails</em> com função de distância com sinal (<em>Signed Distance Function</em>), garantindo ricochetes naturais e atrito preciso nas retas e nas curvas.</li>
  <li><strong>Motor de Áudio Dinâmico:</strong> A rotação do motor altera o <code>playbackRate</code> e volume em tempo real conforme a aceleração. Conta ainda com áudios de baixa latência para frenagem, impacto e largada.</li>
  <li><strong>Feedback Tátil (Haptic Feedback):</strong> Vibrações variáveis que medem a energia do impacto contra as proteções de pista.</li>
  <li><strong>Regras de Corrida Completas:</strong> Contagem regressiva (3, 2, 1, VAI!), tempos de volta e melhor volta, trava anti-trapaça angular e ecrã de bandeirada final.</li>
</ul>

<hr />

<h2>🎮 Mapeamento de Comandos</h2>

<table width="100%">
  <thead>
    <tr>
      <th align="left">Ação</th>
      <th align="center">Teclado</th>
      <th align="center">Gamepad</th>
      <th align="center">Mobile (Touch)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Acelerar</strong></td>
      <td align="center"><code>W</code> / <code>Seta Cima</code></td>
      <td align="center"><code>Botão A</code> / <code>R2</code></td>
      <td align="center">Pedal Verde (Direita)</td>
    </tr>
    <tr>
      <td><strong>Travar / Marcha-atrás</strong></td>
      <td align="center"><code>S</code> / <code>Seta Baixo</code></td>
      <td align="center"><code>Botão B</code> / <code>L2</code></td>
      <td align="center">Pedal Vermelho (Direita)</td>
    </tr>
    <tr>
      <td><strong>Virar Esquerda / Direita</strong></td>
      <td align="center"><code>A</code> / <code>D</code> ou <code>Setas</code></td>
      <td align="center">Analógico / D-Pad</td>
      <td align="center">Setas Tácteis (Esquerda)</td>
    </tr>
    <tr>
      <td><strong>Freio de Mão (Drift)</strong></td>
      <td align="center"><code>Espaço</code></td>
      <td align="center"><code>Botão X</code></td>
      <td align="center">Botão Amarelo (Mão)</td>
    </tr>
    <tr>
      <td><strong>Reiniciar Corrida</strong></td>
      <td align="center"><code>R</code></td>
      <td align="center"><code>Start</code></td>
      <td align="center">Botão no Ecrã Final</td>
    </tr>
    <tr>
      <td><strong>Silenciar Áudio</strong></td>
      <td align="center"><code>M</code></td>
      <td align="center">—</td>
      <td align="center">Ícone Superior de Som</td>
    </tr>
  </tbody>
</table>

<hr />

<h2>📁 Estrutura de Efeitos Sonoros</h2>

<p>Para o funcionamento correto dos efeitos de som, certifique-se de adicionar os ficheiros no diretório <code>assets/audio/</code>:</p>

<pre>
assets/
└── audio/
    ├── engine.wav    # Som do motor em loop contínuo
    ├── skid.wav      # Som de chiado de pneu / derrapagem
    ├── crash.wav     # Som de colisão com a barreira
    ├── beep.wav      # Contagem regressiva (3, 2, 1)
    └── go.wav        # Sinal de largada (VAI!)
</pre>

<p>Registo obrigatório no <code>pubspec.yaml</code>:</p>

<pre><code>flutter:
  assets:
    - assets/audio/
</code></pre>

<hr />

<h2>🚀 Instalação e Execução</h2>

<ol>
  <li>Clone este repositório:
    <pre><code>git clone https://github.com/Edinaldo-long/retro_racing.git</code></pre>
  </li>
  <li>Aceda à pasta do projeto:
    <pre><code>cd retro_racing</code></pre>
  </li>
  <li>Descarregue as dependências:
    <pre><code>flutter pub get</code></pre>
  </li>
  <li>Inicie o jogo:
    <pre><code>flutter run</code></pre>
  </li>
</ol>

<hr />

<div align="center">
  <p>Desenvolvido com 💙 em <strong>Flutter</strong> e <strong>Flame</strong></p>
</div>
