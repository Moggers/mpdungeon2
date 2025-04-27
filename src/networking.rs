use std::thread::JoinHandle;

use arc_swap::ArcSwap;
use tokio::sync::watch;

use crate::state::{Message, State, WorldEntity};

pub struct PlayerCommand {
    pub entity_id: i32,
    pub command_type: String,
    pub x: Option<i16>,
    pub y: Option<i16>,
    pub command_target: Option<i32>,
}

pub struct PlayerMessage {
    pub speaker: i32,
    pub recipient_species: String,
    pub message: String,
}

pub struct ServerConnection {
    pub last_state: &'static ArcSwap<State>,
    pub command_tx: tokio::sync::watch::Sender<Option<PlayerCommand>>,
    pub message_tx: tokio::sync::watch::Sender<Option<PlayerMessage>>,
    pub join_handle: JoinHandle<ExitResult>,
}

pub enum ExitResult {
    LoginFailed,
}

impl ServerConnection {
    #[tokio::main]
    pub async fn start_thread(
        last_state: &ArcSwap<State>,
        conn_addr: String,
        username: String,
        password: String,
        mut command_rx: watch::Receiver<Option<PlayerCommand>>,
        mut message_rx: watch::Receiver<Option<PlayerMessage>>,
    ) -> ExitResult {
        let db_pool = sqlx::PgPool::connect(&conn_addr).await.unwrap();
        let user_ids = sqlx::query_file!("sql/login.sql", username, password)
            .fetch_all(&db_pool)
            .await
            .unwrap();
        let user_id = if user_ids.is_empty() {
            sqlx::query_file!("sql/create_player.sql", username, password)
                .fetch_one(&db_pool)
                .await
                .unwrap()
                .entity_id
        } else {
            if user_ids[0].logged_in {
                user_ids[0].entity_id
            } else {
                return ExitResult::LoginFailed;
            }
        };

        loop {
            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_millis(200))  => {
                },
                _ = message_rx.changed()  => {
                    if let Some(m) = message_rx.borrow_and_update().as_ref() {
                        sqlx::query_file!("sql/say.sql", m.speaker, m.recipient_species, m.message).execute(&db_pool).await.unwrap();
                    }

                }
                _ = command_rx.changed()  => {
                    if let Some(c) = command_rx.borrow_and_update().as_ref() {
                        sqlx::query_file!("sql/insert_command.sql", c.entity_id, c.command_type, c.x, c.y, c.command_target).execute(&db_pool).await.unwrap();
                    }

                }

            };
            let chat = sqlx::query_file_as!(Message, "sql/get_chat.sql", user_id)
                .fetch_all(&db_pool)
                .await
                .unwrap();
            let entities = sqlx::query_file_as!(WorldEntity, "sql/get_world_entities.sql", user_id)
                .fetch_all(&db_pool)
                .await
                .unwrap();
            last_state.store(
                State {
                    entities,
                    chat,
                    self_entity_id: Some(user_id),
                }
                .into(),
            );
        }
    }

    pub fn create_commmand(&self, cmd: PlayerCommand) {
        self.command_tx.send(Some(cmd)).unwrap();
    }
    pub fn say(&self, msg: PlayerMessage) {
        self.message_tx.send(Some(msg)).unwrap();
    }

    pub fn new(server_addr: String, username: String, password: String) -> Self {
        let (command_tx, command_rx) = tokio::sync::watch::channel(None);
        let (message_tx, message_rx) = tokio::sync::watch::channel(None);
        let last_state: &_ = Box::leak(Box::new(ArcSwap::new(
            State {
                entities: vec![],
                chat: vec![],
                self_entity_id: None,
            }
            .into(),
        )));
        let join_handle = std::thread::spawn(move || {
            Self::start_thread(
                last_state,
                server_addr,
                username,
                password,
                command_rx,
                message_rx,
            )
        });

        Self {
            last_state,
            command_tx,
            join_handle,
            message_tx,
        }
    }
}
