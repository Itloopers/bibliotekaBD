--TABELE--
create type rola as enum(
	'nowy czytelnik',
	'czytelnik',
	'obsluga'
);

create table kraj (
	id serial not null,
	kraj varchar(100) not null,
	constraint rola_pkey primary key (id)
);

create table jezyk (
	id serial not null,
	jezyk varchar(100) not null,
	constraint jezyk_pkey primary key (id)
);

create table rodzaj (
	id serial not null,
	nazwa varchar(150) not null,
	constraint rodzaj_pkey primary key (id)
);

-- Tworzy typ dla hasła użytkownika.
CREATE EXTENSION chkpass;
create table uzytkownik(
	id serial not null,
	imie varchar(100) not null,
	nazwisko varchar(100) not null,
	rola rola,
	nazwa varchar(250) unique,
	haslo chkpass,
	constraint uzytkownik_pkey primary key (id)
);

create table autor(
	id serial not null,
	imie varchar(255) not null,
	drugie_imie varchar(255),
	nazwisko varchar(255) not null,
	kraj integer,
	constraint autor_pkey primary key (id),
	constraint fk_autor_kraj foreign key (kraj)
		references kraj (id) match simple
		on update no action on delete no action
);

create table ksiazka(
	id serial not null,
	tytul varchar(255) not null,
	autor integer not null,
	autor_2 integer,
	rok integer not null,
	isbn varchar(13),
	rodzaj integer,
	jezyk integer,
	ilosc_stron integer,
	constraint ksiazka_pkey primary key (id),
	constraint fk_ksiazka_autor foreign key (autor)
		references autor (id) match simple
		on update no action on delete no action,
	constraint fk_ksiazka_autor_2 foreign key (autor_2)
		references autor (id) match simple
		on update no action on delete no action,
	constraint fk_ksiazka_rodzaj foreign key (rodzaj)
		references rodzaj (id) match simple
		on update no action on delete no action,
	constraint fk_ksiazka_jezyk foreign key (jezyk)
		references jezyk (id) match simple
		on update no action on delete no action
);

create table ksiazki_zasoby(
	id serial not null,
	ksiazka integer not null,
	dostepne integer not null,
	wypozyczone integer not null,
	constraint ksiazki_zasoby_pkey primary key (id),
	constraint fk_ksiazki_zasoby_ksiazka foreign key (ksiazka)
		references ksiazka (id) match simple
		on update no action on delete no action
);

create table wypozyczenia(
	id serial not null,
	uzytkownik integer not null,
	ksiazka integer not null,
	data_wypozyczenia timestamp not null,
	data_zwrocenia timestamp,
	constraint wypozyczenia_pkey primary key (id),
	constraint fk_wypozyczenia_uzytkownik foreign key (uzytkownik)
		references uzytkownik (id) match simple
		on update no action on delete no action,
	constraint fk_wypozyczenia_ksiazka foreign key (ksiazka)
		references ksiazka (id) match simple
		on update no action on delete no action
);

--FUNKCJE--
--1 Wyświetla wszystkich autorów jako jedna kolumne.
create or replace function wyswietl_autorow(imie varchar, drugie_imie varchar, nazwisko varchar,imie2 varchar, 
											drugie_imie2 varchar, nazwisko2 varchar) returns varchar as 
$BODY$
	begin
		if imie2 is null then
			return format('%s %s %s',$1,$2,$3);
		else 
			return format('%s %s %s, %s %s %s',imie, drugie_imie, nazwisko, imie2, drugie_imie2, nazwisko2);
		end if;
	end;
$BODY$
language plpgsql;

--2. Generuje nazwe dla osoby/uzytkownika, który jest też loginem dla obsługi. Wyzwalane poprze trigger generuj_nazwe_trigger
create or replace function generuj_nazwe() returns trigger as
$BODY$
begin
	update uzytkownik
	set nazwa = lower(left(new.imie,1)||'_'||new.nazwisko||new.id)
	where nazwa is null;
	return new;
end;
$BODY$
language plpgsql;


--3 Wywolywane przez trigger sprawdz_isbn_trigger sprawdzenie isbn czy jest prawidlowy
create or replace function sprawdz_isbn() returns trigger as
$BODY$
declare
	wartoscKontrolna int;
	suma int;
	cyfra int;
begin
	if new.isbn is null then
		return new;
	end if;

	wartoscKontrolna = right(new.isbn,1) as integer;
	suma = 0;
	
	for i in 1..12 loop
		cyfra = substr(new.isbn,i,1) as integer;
		if i%2 = 0 then
			suma = cyfra*3 + suma;
		else 
			suma = cyfra*1 + suma;
		end if;
	end loop;
	suma = suma % 10;
	if suma <> 0 then
		suma = 10 - suma;
	end if;
	if suma = wartoscKontrolna then
		return new;
	else
		raise using message='Wprowadzono błędny isbn.';
	end if;
end;
$BODY$
language plpgsql;

--4 Wywoływane prze trigger wypozycz_ksiazke_trigger sprawdzenie czy uzytkownik ma juz dana ksiazke na stanie.
create or replace function sprawdz_wypozyczone() returns trigger as
$BODY$
declare
	juzWypozyczyl integer;
begin
	juzWypozyczyl := count(id) from wypozyczenia where ksiazka = new.ksiazka and uzytkownik = new.uzytkownik and data_zwrocenia is null;
	
	if juzWypozyczyl > 0 then
		raise using message=format('%I ma juz ksiazke %I',new.uzytkownik,new.ksiazka);
	else
		return new;
	end if;
end;
$BODY$
language plpgsql;

--5 Wypozycz ksiażke (uzytkownik.id,) czas pobierany z bazy.
create or replace function wypozycz_ksiazke(uzytkownik integer, ksiazkaId integer) returns void as
$BODY$
declare
	ksiazkavar integer;
begin
	ksiazkavar := dostepne from ksiazki_zasoby where ksiazka = $2;
	if  ksiazkavar > 0 then
		insert into wypozyczenia(uzytkownik,ksiazka,data_wypozyczenia) values($1,$2,now());
	else
		raise using message='Wszystkie ksiazki wypozyczone';
	end if;	
end;
$BODY$
language 'plpgsql';

/* depreciated--5 Wypozycz ksiażke (uzytkownik.id,) czas pobierany z bazy.
create or replace function wypozycz_ksiazke(uzytkownik integer, ksiazka integer) returns void as
$BODY$
	insert into wypozyczenia(uzytkownik,ksiazka,data_wypozyczenia) values($1,$2,now());
$BODY$
language 'sql';
*/

--6 Zwroc ksiażke (uzytkownik.id,) czas pobierany z bazy.
create or replace function zwroc_ksiazke(uzytkownikId integer, ksiazkaId integer) returns interval as
$BODY$
declare
	idWypozyczenia integer;
begin
	idWypozyczenia := id from wypozyczenia where uzytkownik = $1 and ksiazka = $2 and data_zwrocenia is null;

	update wypozyczenia
	set data_zwrocenia = now()
	where id = idWypozyczenia;
	
	update uzytkownik
	set rola = awans_uzytkownika(uzytkownikId)
	where id = uzytkownikId;
	
	return data_zwrocenia-data_wypozyczenia as "czas_wypozyczenia"
	from wypozyczenia
	where id = idWypozyczenia;
end;	
$BODY$
language 'plpgsql';

--7 Zaaktualizuj ksiazki_zasoby po wypozyczeniu/zwroceniu ksiazki
create or replace function zaaktualizuj_ksiazki_zasoby() returns trigger as
$BODY$
begin
	if TG_OP = 'UPDATE' then
		update ksiazki_zasoby
		set dostepne = dostepne+1, wypozyczone = wypozyczone-1
		where ksiazka = new.ksiazka;
	else
		update ksiazki_zasoby
		set dostepne = dostepne -1, wypozyczone = wypozyczone +1
		where ksiazka = new.ksiazka;
	end if;
	return new;
end;
$BODY$
language 'plpgsql';

--8 Awans uzytkownika
create or replace function awans_uzytkownika(uzytkownikId integer) returns rola as
$BODY$
declare 
	rolavar rola;
	iloscKsiazek integer;
begin
	rolavar := rola from uzytkownik where id = uzytkownikId;
	iloscKsiazek := count(id) from wypozyczenia 
					where uzytkownik = uzytkownikId and data_zwrocenia is not null;
					
	if rolavar = 'nowy czytelnik' and iloscKsiazek >= 5 then
		return 'czytelnik';
	else 
		return rolavar;
	end if;
end;
$BODY$
language 'plpgsql';

--TRIGGERY--
--1 trigger dla generowania nazwy dla uzytkownika.
create trigger generuj_nazwe_trigger
after insert on uzytkownik
for row
execute procedure generuj_nazwe();

--2 Sprawdzenie isbn podczas dodawania ksiazki.
create trigger sprawdz_isbn_trigger
after insert or update on ksiazka
for row
execute procedure sprawdz_isbn();

--3 Sprawdzeni czy ponownie mozna wyporzyczyc ksiazke.
create trigger wypozycz_ksiazke_trigger
before insert on wypozyczenia
for row
execute procedure sprawdz_wypozyczone();

--4 Aktualizacja zasobow po wypozyczeniu(insert), zwroceniu(update)
create trigger zasoby_ksiazki_wypozycz_zwroc_ksiazke_trigger
after insert or update on wypozyczenia
for row
execute procedure zaaktualizuj_ksiazki_zasoby();

/*depreciated
--4 Akualizacja zasobow po wypozyczeniu. polaczone w (zasoby_ksiazki_wypozycz_zwroc_ksiazke_trigger)
create trigger zasoby_ksiazki_wypozycz_ksiazke_trigger
after insert on wypozyczenia
for row
execute procedure zaaktualizuj_ksiazki_zasoby();

--5 Aktualizacja zasobow po zwroceniu. polaczone w (zasoby_ksiazki_wypozycz_zwroc_ksiazke_trigger)
create trigger zasoby_ksiazki_zwroc_ksiazke_trigger
after update on wypozyczenia
for row
execute procedure zaaktualizuj_ksiazki_zasoby();
*/

--widoki 2
--Prosty widok ksiązek.
create or replace view lista_ksiazek as
select k.id, k.tytul, k.rok, wyswietl_autorow(a.imie,a.drugie_imie,a.nazwisko,a2.imie,a2.drugie_imie,a2.nazwisko) as autor, 
	j.jezyk, r.nazwa as rodzaj, k.isbn, k.ilosc_stron
from ksiazka k left join autor a2 on k.autor_2=a2.id, autor a, jezyk j, rodzaj r
where k.autor = a.id and k.jezyk = j.id and k.rodzaj = r.id
order by tytul;

--Pełny widok ksiazek.
create or replace view pełna_lista_ksiazek as
select k.id, k.tytul, k.rok, k.autor as autor_1, k.autor_2, wyswietl_autorow(a.imie,a.drugie_imie,a.nazwisko,a2.imie,a2.drugie_imie,a2.nazwisko) as "autor 1,2",
	k.jezyk as id_jezyk, j.jezyk, k.rodzaj as id_rodzaj, r.nazwa as rodzaj, k.isbn, k.ilosc_stron
from ksiazka k 
	left join autor a2 on k.autor_2=a2.id
	left join rodzaj r on k.rodzaj=r.id
	left join jezyk j on k.jezyk=j.id,
	autor a
where k.autor = a.id
order by tytul asc;
