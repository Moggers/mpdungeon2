pub struct WorldEntity {
    pub entity_id: i32,
    pub x: i16,
    pub y: i16,
    pub species: Option<String>,
    pub command_type: Option<String>,
    pub command_x: Option<i16>,
    pub command_y: Option<i16>,
    pub hp: Option<i32>,
    pub maxhp: Option<i32>,
    pub ends: Option<Vec<i32>>,
}
pub struct State {
    pub entities: Vec<WorldEntity>,
    pub self_entity_id: Option<i32>,
}
