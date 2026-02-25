--Date as datatype doesnt exist--
CREATE TABLE TitleAuthor (
	TitleID int NOT NULL,
	AuthorID int NOT NULL,
	AuthorOrder int NOT NULL
	);

CREATE TABLE Customer (
	CustomerID int NOT NULL,
	FirstName varchar(30) NOT NULL,
	LastName varchar(30) NOT NULL,
	Address varchar(50) NULL,
	City varchar(50) NULL,
	State varchar(5) NULL,
	Zip varchar(10) NULL,
	Country varchar(50) NULL
	);

CREATE TABLE OrderHeader (
	OrderID int NOT NULL,
    CustomerID int NOT NULL,
    PromotionID int NULL,
	OrderDate date NOT NULL
    );

CREATE TABLE OrderItem (
	OrderID int NOT NULL,
    OrderItem int NOT NULL,
    TitleID int NOT NULL,
    Quantity int NOT NULL,
    ItemPrice decimal (5,2) NOT NULL
    );

CREATE TABLE Promotion (
	PromotionID int NOT NULL,
    PromotionCode varchar(10) NOT NULL,
    PromotionStartDate date NOT NULL,
    PromotionEndDate date NOT NULL
    );

CREATE TABLE MyFirstQuery (
	Outcome VARCHAR(20) NOT NULL
	);