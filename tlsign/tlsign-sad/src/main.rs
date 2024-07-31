#![allow(dead_code, unused_mut, unused_variables, clippy::let_and_return)]

use std::{
    io,
    net::TcpStream,
    sync::{Arc, Mutex},
    time::Duration,
};

use rustls::{pki_types::UnixTime, time_provider::TimeProvider};

#[derive(Debug)]
enum TimeGenerator {
    Record(Mutex<Vec<UnixTime>>),
    Replay(Mutex<usize>, Vec<UnixTime>),
}

impl TimeGenerator {
    fn record() -> Self {
        Self::Record(Mutex::new(Vec::new()))
    }

    fn replay(times: Vec<UnixTime>) -> Self {
        Self::Replay(Mutex::new(0), times)
    }
}

impl TimeProvider for TimeGenerator {
    fn current_time(&self) -> Option<UnixTime> {
        match self {
            TimeGenerator::Record(times) => {
                let mut times = times.lock().unwrap();
                let time = UnixTime::now();
                times.push(time);
                Some(time)
            }
            TimeGenerator::Replay(idx, times) => {
                let mut idx = idx.lock().unwrap();
                let time = times.get(*idx).copied();
                *idx += 1;
                time
            }
        }
    }
}

#[derive(Debug, Default, Clone)] // TODO: sensible Debug impl
struct Transcript {
    read: Vec<Vec<u8>>,
    write: Vec<Vec<u8>>,
}

enum ConnectionConfig {
    Record,
    Replay {
        seed: [u8; 32],
        times: Vec<UnixTime>,
        transcript: Transcript,
    },
}

#[derive(Debug)]
enum Socket {
    Real {
        socket: TcpStream,
        transcript: Arc<Mutex<Transcript>>,
    },
    Emulated {
        transcript: Transcript,
        read_cursor: usize,
        write_cursor: usize,
    },
}

impl io::Read for Socket {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Socket::Real { socket, transcript } => {
                let count = socket.read(buf)?;
                eprintln!("Socket::read: before transcript.lock()");
                transcript
                    .lock()
                    .unwrap()
                    .read
                    .push(buf[..count].to_owned());
                eprintln!("Socket::read: after transcript.lock(), returning {count}");
                Ok(count)
            }
            Socket::Emulated {
                transcript,
                read_cursor,
                write_cursor: _,
            } => {
                let msg = &transcript.read[*read_cursor];
                if msg.len() > buf.len() {
                    panic!("too small buffer provided");
                }
                buf[..msg.len()].copy_from_slice(msg);
                *read_cursor += 1;
                Ok(msg.len())
            }
        }
    }
}

impl io::Write for Socket {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            Socket::Real { socket, transcript } => {
                let count = socket.write(buf)?;
                transcript
                    .lock()
                    .unwrap()
                    .write
                    .push(buf[..count].to_owned());
                Ok(count)
            }
            Socket::Emulated {
                transcript,
                read_cursor: _,
                write_cursor,
            } => {
                let count = transcript.write[*write_cursor].len();
                assert_eq!(&transcript.write[*write_cursor], buf);
                *write_cursor += 1;
                Ok(count)
            }
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self {
            Socket::Real { socket, .. } => socket.flush(),
            Socket::Emulated { .. } => Ok(()),
        }
    }
}

#[derive(Debug)]
struct Connection {
    tls: rustls::ClientConnection,
    socket: Socket,
}

impl io::Read for Connection {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        eprintln!("before Connection::read()");
        loop {
            eprintln!("Connection::read: before read_tls");
            self.tls.read_tls(&mut self.socket)?;
            self.tls
                .process_new_packets()
                .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
            let res = self.tls.reader().read(buf);
            if let Err(err) = &res {
                // rustls produces spurious WouldBlock
                if err.kind() == io::ErrorKind::WouldBlock {
                    // Don't block, read more.
                    continue;
                }
            }
            eprintln!("returning {res:?} from Connection::read()");
            break res;
        }
    }
}

impl io::Write for Connection {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let count = self.tls.writer().write(buf)?;
        self.tls.write_tls(&mut self.socket)?;
        Ok(count)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.tls.writer().flush()?;
        self.tls.write_tls(&mut self.socket)?;
        Ok(())
    }
}

impl ureq::ReadWrite for Connection {
    fn socket(&self) -> Option<&TcpStream> {
        // No direct access to the underlying socket, sry
        None
    }
}

struct Connector {
    config: ConnectionConfig,
    time_provider: Arc<TimeGenerator>,
    transcript: Arc<Mutex<Transcript>>,
}

impl Connector {
    fn new(config: ConnectionConfig) -> Self {
        let time_provider = Arc::new(match &config {
            ConnectionConfig::Record => TimeGenerator::record(),
            ConnectionConfig::Replay { times, .. } => TimeGenerator::replay(times.clone()),
        });
        let transcript = Arc::new(Mutex::new(Transcript::default()));
        Self {
            config,
            time_provider,
            transcript,
        }
    }
}

impl ureq::TlsConnector for Connector {
    fn connect(
        &self,
        dns_name: &str,
        _io: Box<dyn ureq::ReadWrite>,
    ) -> Result<Box<dyn ureq::ReadWrite>, ureq::Error> {
        // We completely ignore provided `_io` and establish our own connection.
        // I sure hope that won't bite us later.

        let time_provider = Arc::clone(&self.time_provider) as _;
        let root_store = {
            let mut roots = rustls::RootCertStore::empty();
            roots.add_parsable_certificates(rustls_native_certs::load_native_certs()?);
            roots
        };

        let mut client_config = rustls::ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();
        client_config.time_provider = Arc::clone(&time_provider);
        let tls = rustls::ClientConnection::new(
            Arc::new(client_config),
            dns_name
                .to_owned()
                .try_into()
                .expect("failed to convert DNS name"),
        )
        .expect("failed to create ClientConnection");

        let socket = match &self.config {
            ConnectionConfig::Record => {
                eprintln!("before TcpStream::connect({dns_name:?})");
                let tcp = TcpStream::connect((dns_name, 443))?;
                eprintln!("after TcpStream::connect({dns_name:?})");
                Socket::Real {
                    socket: tcp,
                    transcript: Arc::clone(&self.transcript),
                }
            }
            ConnectionConfig::Replay { transcript, .. } => Socket::Emulated {
                transcript: transcript.clone(),
                read_cursor: 0,
                write_cursor: 0,
            },
        };

        eprintln!("created Connection");
        Ok(Box::new(Connection { tls, socket }) as _)
    }
}

fn run(config: ConnectionConfig, url: &str) {
    let _seed = match config {
        ConnectionConfig::Record => getrandom::_seed_random(),
        ConnectionConfig::Replay { seed, .. } => {
            getrandom::_seed(seed);
            seed
        }
    };
    let connector = Connector::new(config);
    let agent = ureq::builder()
        .tls_connector(Arc::new(connector))
        .timeout(Duration::from_secs(600))
        .timeout_read(Duration::from_secs(600))
        .timeout_write(Duration::from_secs(600))
        .build();
    let response = agent.get(url).call().unwrap();
    dbg!(response);
}

fn main() {
    run(ConnectionConfig::Record, "https://example.com");
}
