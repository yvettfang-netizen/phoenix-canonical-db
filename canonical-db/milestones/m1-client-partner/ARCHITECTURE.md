# M1 Architecture — Client & Partner Relationships

M1 extends the existing Family-mapped `crm.clients` authority. It does not create a second Client, Person, Family, Organization or employee identity.

- Client remains a time-bounded commercial relationship to exactly one Family.
- Client parties express Payer, Contract Party, Client Contact, Service Recipient and Authorized Representative separately; no role is inferred from Family administrator status.
- Partner relationships point to either one canonical Person or one canonical Organization. Partner is a commercial role, not an Employee/Principal synonym.
- Referral/Channel partners must bind an existing active Lead Source, preserving channel ownership.
- Client and Partner status changes append immutable event history. Ended history is retained; later re-establishment uses a new UUID and non-overlapping validity.

The Enterprise Core SERVICE owns Client creation/lifecycle. The CRM SERVICE owns Client-party and Partner relationships. All writes use the existing one-use context ticket and controlled database API.
