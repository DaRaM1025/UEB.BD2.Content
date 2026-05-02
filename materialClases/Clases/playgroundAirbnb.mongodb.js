
db.listingsAndReviews.find({
    'address.country': 'United States',
    'address.market': 'New York',
    $expr: {
        $eq: [
            { $year: "$first_review" },
            new Date().getFullYear() - 5
        ]
    }
});

use('sample_airbnb');
db.listingsAndReviews.find({
    'property_type': 'Apartment',
    $or: [
         {amenities: {$elemMatch: {$eq: 'TV'}}},
         {amenities: {$elemMatch: {$eq: 'Wifi'}}}
    ]
}, 
    {amenities: 1, property_type: 1, }
)


db.listingsAndReviews.aggregate({
    {$group: { "_id": "$address.market",
         totalPrices: {$sum: "$price"}}}
    })
    
